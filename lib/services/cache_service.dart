import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:JASA/services/image_cache_service.dart';

/// CacheService handles all caching operations for fast data retrieval
/// Pre-loads products, categories, and images at app startup
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  // Image cache service
  final ImageCacheService _imageCacheService = ImageCacheService();

  // Hive box names
  static const String _productsBoxName = 'products_cache';
  static const String _categoriesBoxName = 'categories_cache';
  static const String _metaBoxName = 'cache_meta';

  // Cache expiry duration (30 minutes for data, images are permanent)
  static const Duration _cacheExpiry = Duration(minutes: 30);

  // Boxes
  late Box<Map> _productsBox;
  late Box<Map> _categoriesBox;
  late Box _metaBox;

  // In-memory cache for faster access
  List<Map<String, dynamic>> _cachedProducts = [];
  List<Map<String, dynamic>> _cachedCategories = [];

  // Getters for cached data
  List<Map<String, dynamic>> get products => _cachedProducts;
  List<Map<String, dynamic>> get categories => _cachedCategories;

  // Initialization flag
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Initialize Hive and open boxes
  Future<void> init({bool skipHiveInit = false}) async {
    if (_isInitialized) return;

    try {
      if (!skipHiveInit) {
        await Hive.initFlutter();
      }

      _productsBox = await Hive.openBox<Map>(_productsBoxName);
      _categoriesBox = await Hive.openBox<Map>(_categoriesBoxName);
      _metaBox = await Hive.openBox(_metaBoxName);

      // Initialize image cache service
      await _imageCacheService.init();

      _isInitialized = true;

      // Load cached data into memory
      await _loadCachedData();
    } catch (e) {
      debugPrint('CacheService init error: $e');
      _isInitialized = true; // Mark as initialized to prevent repeated attempts
    }
  }


  /// Load cached data from Hive into memory
  Future<void> _loadCachedData() async {
    // Load products from cache
    if (_productsBox.isNotEmpty) {
      _cachedProducts = _productsBox.values
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    // Load categories from cache
    if (_categoriesBox.isNotEmpty) {
      _cachedCategories = _categoriesBox.values
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
  }

  /// Check if cache is valid (not expired)
  bool _isCacheValid() {
    final lastUpdate = _metaBox.get('lastUpdate');
    if (lastUpdate == null) return false;

    final lastUpdateTime = DateTime.parse(lastUpdate as String);
    return DateTime.now().difference(lastUpdateTime) < _cacheExpiry;
  }

  /// Check network connectivity
  Future<bool> _hasNetworkConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return !connectivityResult.contains(ConnectivityResult.none);
  }

  /// Refresh all data from Supabase and cache it
  /// This is called at app startup
  Future<void> refreshAllData({
    bool forceRefresh = false,
    Function(String message, double progress)? onProgress,
  }) async {
    if (!_isInitialized) await init();

    // Check if we need to refresh
    if (!forceRefresh && _isCacheValid() && _cachedProducts.isNotEmpty) {
      onProgress?.call('Using cached data...', 0.5);
      
      // Still check for new images in background if online
      final hasNetwork = await _hasNetworkConnection();
      if (hasNetwork) {
        _cacheNewImages();
      }
      
      onProgress?.call('Ready!', 1.0);
      return;
    }

    // Check network connectivity
    final hasNetwork = await _hasNetworkConnection();
    if (!hasNetwork) {
      if (_cachedProducts.isNotEmpty) {
        onProgress?.call('Offline - using cached data', 1.0);
        return;
      } else {
        throw Exception('No network connection and no cached data available');
      }
    }

    try {
      final supabase = Supabase.instance.client;

      // Step 1: Fetch products
      onProgress?.call('Loading products...', 0.15);
      final productsResponse = await supabase
          .from('products')
          .select()
          .order('sort_order', ascending: true);
      
      _cachedProducts = List<Map<String, dynamic>>.from(productsResponse as List);

      // Step 2: Fetch categories
      onProgress?.call('Loading categories...', 0.3);
      final categoriesResponse = await supabase
          .from('categories')
          .select()
          .order('name');
      
      _cachedCategories = List<Map<String, dynamic>>.from(categoriesResponse as List);

      // Step 3: Save to Hive
      onProgress?.call('Saving data...', 0.4);
      await _saveToHive();

      // Step 4: Pre-cache all product images (with progress)
      onProgress?.call('Downloading images...', 0.5);
      await _imageCacheService.cacheAllProductImages(
        _cachedProducts,
        onProgress: (current, total) {
          final imageProgress = 0.5 + (current / total) * 0.45;
          onProgress?.call('Caching images ($current/$total)...', imageProgress);
        },
      );

      onProgress?.call('Ready!', 1.0);

    } catch (e) {
      debugPrint('Error refreshing cache: $e');
      // If we have cached data, use it
      if (_cachedProducts.isEmpty) {
        rethrow;
      }
    }
  }

  /// Cache any new images that aren't already cached
  Future<void> _cacheNewImages() async {
    try {
      await _imageCacheService.cacheAllProductImages(_cachedProducts);
    } catch (e) {
      debugPrint('Background image caching failed: $e');
    }
  }

  /// Save data to Hive for persistence
  Future<void> _saveToHive() async {
    // Clear and save products
    await _productsBox.clear();
    for (int i = 0; i < _cachedProducts.length; i++) {
      await _productsBox.put(i, _cachedProducts[i]);
    }

    // Clear and save categories
    await _categoriesBox.clear();
    for (int i = 0; i < _cachedCategories.length; i++) {
      await _categoriesBox.put(i, _cachedCategories[i]);
    }

    // Update metadata
    await _metaBox.put('lastUpdate', DateTime.now().toIso8601String());
  }

  /// Get image URL for a product (uses Supabase storage URL)
  String? getProductImageUrl(Map<String, dynamic> product) {
    if (product['image_path'] == null) return null;
    
    return Supabase.instance.client.storage
        .from('product-images')
        .getPublicUrl(product['image_path']);
  }

  /// Get image path for a product (for local cache lookup)
  String? getProductImagePath(Map<String, dynamic> product) {
    return product['image_path'] as String?;
  }

  /// Check if a product's image is cached locally
  bool isImageCached(Map<String, dynamic> product) {
    final imagePath = product['image_path'] as String?;
    if (imagePath == null) return false;
    return _imageCacheService.isImageCached(imagePath);
  }

  /// Get products by category
  List<Map<String, dynamic>> getProductsByCategory(String? categoryCode) {
    if (categoryCode == null) return _cachedProducts;
    return _cachedProducts
        .where((p) => p['category_code'] == categoryCode)
        .toList();
  }

  /// Search products by name
  List<Map<String, dynamic>> searchProducts(String query) {
    if (query.isEmpty) return _cachedProducts;
    final lowerQuery = query.toLowerCase();
    return _cachedProducts
        .where((p) => (p['name'] as String).toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// Update a single product in cache (after local modification)
  void updateProduct(Map<String, dynamic> product) {
    final index = _cachedProducts.indexWhere(
        (p) => p['product_id'] == product['product_id']);
    if (index != -1) {
      _cachedProducts[index] = product;
      _productsBox.put(index, product);
      
      // Update image cache if image changed
      if (product['image_path'] != null) {
        _imageCacheService.updateProductImage(product['image_path']);
      }
    }
  }

  /// Add a new product to cache
  void addProduct(Map<String, dynamic> product) {
    _cachedProducts.add(product);
    _productsBox.put(_cachedProducts.length - 1, product);
    
    // Cache the new product's image
    if (product['image_path'] != null) {
      _imageCacheService.cacheImage(product['image_path']);
    }
  }

  /// Remove a product from cache
  void removeProduct(String productId) {
    final product = _cachedProducts.firstWhere(
      (p) => p['product_id'] == productId,
      orElse: () => {},
    );
    
    // Remove image from cache
    if (product['image_path'] != null) {
      _imageCacheService.removeImage(product['image_path']);
    }
    
    _cachedProducts.removeWhere((p) => p['product_id'] == productId);
    // Rebuild Hive storage
    _saveToHive();
  }

  /// Update product stock after billing
  void updateProductStock(String productId, int newStock) {
    final index = _cachedProducts.indexWhere((p) => p['product_id'] == productId);
    if (index != -1) {
      _cachedProducts[index]['stock'] = newStock;
      _productsBox.put(index, _cachedProducts[index]);
    }
  }

  /// Force refresh data from server
  Future<void> forceRefresh({
    Function(String message, double progress)? onProgress,
  }) async {
    await refreshAllData(forceRefresh: true, onProgress: onProgress);
  }

  /// Clear all cached data
  Future<void> clearCache() async {
    await _productsBox.clear();
    await _categoriesBox.clear();
    await _metaBox.clear();
    await _imageCacheService.clearAllImages();
    _cachedProducts = [];
    _cachedCategories = [];
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    final imageSize = await _imageCacheService.getFormattedCacheSize();
    return {
      'productCount': _cachedProducts.length,
      'categoryCount': _cachedCategories.length,
      'cachedImageCount': _imageCacheService.cachedImageCount,
      'imageCacheSize': imageSize,
      'lastUpdate': _metaBox.get('lastUpdate'),
    };
  }
}
