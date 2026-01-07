import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// ImageCacheService handles persistent image caching for offline access
/// Images are stored in the device's file system and only updated when needed
class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  // Hive box for image metadata
  static const String _imageMetaBoxName = 'image_cache_meta';
  Box<Map>? _imageMetaBox;

  // Local cache directory
  Directory? _cacheDir;

  // Initialization flag
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool get isInitialized => _isInitialized;

  // Cache version - increment this to force re-download all images
  static const int _cacheVersion = 1;

  /// Initialize the image cache service
  Future<void> init() async {
    if (_isInitialized) return;
    if (_isInitializing) return; // Prevent re-entrant calls
    
    _isInitializing = true;
    
    try {
      // Open Hive box for metadata
      _imageMetaBox = await Hive.openBox<Map>(_imageMetaBoxName);

      // Get cache directory
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${appDir.path}/product_images');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }

      // Check cache version and clear if outdated
      final storedVersion = _imageMetaBox?.get('_version');
      if (storedVersion == null || storedVersion['version'] != _cacheVersion) {
        await _clearAllImagesInternal();
        await _imageMetaBox?.put('_version', {'version': _cacheVersion});
      }

      _isInitialized = true;
      debugPrint('📸 ImageCacheService initialized at ${_cacheDir?.path}');
    } catch (e) {
      debugPrint('❌ ImageCacheService init error: $e');
      // Mark as initialized to prevent repeated attempts
      _isInitialized = true;
    } finally {
      _isInitializing = false;
    }
  }

  /// Check if image is cached locally
  bool isImageCached(String imagePath) {
    if (_imageMetaBox == null) return false;
    
    try {
      final meta = _imageMetaBox!.get(imagePath);
      if (meta == null) return false;

      final filePath = meta['localPath'] as String?;
      if (filePath == null) return false;

      return File(filePath).existsSync();
    } catch (e) {
      return false;
    }
  }

  /// Get local file path for a cached image
  String? getLocalImagePath(String imagePath) {
    if (_imageMetaBox == null) return null;
    
    try {
      final meta = _imageMetaBox!.get(imagePath);
      if (meta == null) return null;

      final filePath = meta['localPath'] as String?;
      if (filePath == null) return null;

      final file = File(filePath);
      if (file.existsSync()) {
        return filePath;
      }
    } catch (e) {
      debugPrint('Error getting local image path: $e');
    }
    return null;
  }

  /// Get image file for display (returns File if cached, null if needs download)
  File? getCachedImageFile(String imagePath) {
    final localPath = getLocalImagePath(imagePath);
    if (localPath != null) {
      return File(localPath);
    }
    return null;
  }

  /// Download and cache an image
  Future<String?> cacheImage(String imagePath, {bool forceRedownload = false}) async {
    if (!_isInitialized) {
      await init();
    }
    
    if (_cacheDir == null || _imageMetaBox == null) {
      return null;
    }

    // Check if already cached
    if (!forceRedownload && isImageCached(imagePath)) {
      return getLocalImagePath(imagePath);
    }

    try {
      // Get public URL from Supabase
      final imageUrl = Supabase.instance.client.storage
          .from('product-images')
          .getPublicUrl(imagePath);

      // Download image
      final response = await http.get(Uri.parse(imageUrl)).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        // Generate local file name
        final fileName = imagePath.replaceAll('/', '_').replaceAll('\\', '_');
        final localPath = '${_cacheDir!.path}/$fileName';

        // Save to file
        final file = File(localPath);
        await file.writeAsBytes(response.bodyBytes);

        // Save metadata
        await _imageMetaBox!.put(imagePath, {
          'localPath': localPath,
          'imageUrl': imageUrl,
          'cachedAt': DateTime.now().toIso8601String(),
          'size': response.bodyBytes.length,
        });

        debugPrint('📸 Cached image: $imagePath -> $localPath');
        return localPath;
      } else {
        debugPrint('❌ Failed to download image: $imagePath (${response.statusCode})');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error caching image $imagePath: $e');
      return null;
    }
  }

  /// Pre-cache all product images
  Future<void> cacheAllProductImages(
    List<Map<String, dynamic>> products, {
    Function(int current, int total)? onProgress,
  }) async {
    if (!_isInitialized) {
      await init();
    }
    
    if (_imageMetaBox == null) return;

    try {
      // Check network connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        debugPrint('📶 Offline - skipping image pre-cache');
        return;
      }

      final imagesToCache = products
          .where((p) => p['image_path'] != null && !isImageCached(p['image_path']))
          .toList();

      if (imagesToCache.isEmpty) {
        debugPrint('✅ All images already cached');
        return;
      }

      debugPrint('📸 Caching ${imagesToCache.length} images...');

      int cached = 0;
      for (final product in imagesToCache) {
        final imagePath = product['image_path'] as String;
        await cacheImage(imagePath);
        cached++;
        onProgress?.call(cached, imagesToCache.length);
      }

      debugPrint('✅ Cached $cached images');
    } catch (e) {
      debugPrint('Error caching product images: $e');
    }
  }

  /// Update image cache for a specific product (e.g., after product edit)
  Future<void> updateProductImage(String imagePath) async {
    await cacheImage(imagePath, forceRedownload: true);
  }

  /// Remove a cached image
  Future<void> removeImage(String imagePath) async {
    try {
      final localPath = getLocalImagePath(imagePath);
      if (localPath != null) {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      await _imageMetaBox?.delete(imagePath);
    } catch (e) {
      debugPrint('Error removing image: $e');
    }
  }

  /// Internal clear method (doesn't call init)
  Future<void> _clearAllImagesInternal() async {
    try {
      // Delete all files in cache directory
      if (_cacheDir != null && await _cacheDir!.exists()) {
        final files = _cacheDir!.listSync();
        for (final file in files) {
          if (file is File) {
            await file.delete();
          }
        }
      }

      // Clear metadata (except version)
      if (_imageMetaBox != null) {
        final version = _imageMetaBox!.get('_version');
        await _imageMetaBox!.clear();
        if (version != null) {
          await _imageMetaBox!.put('_version', version);
        }
      }

      debugPrint('🗑️ Cleared all cached images');
    } catch (e) {
      debugPrint('Error clearing images: $e');
    }
  }

  /// Clear all cached images
  Future<void> clearAllImages() async {
    if (!_isInitialized) {
      await init();
    }
    await _clearAllImagesInternal();
  }

  /// Get cache size in bytes
  Future<int> getCacheSize() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;

    try {
      int totalSize = 0;
      final files = _cacheDir!.listSync();
      for (final file in files) {
        if (file is File) {
          totalSize += await file.length();
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  /// Get formatted cache size
  Future<String> getFormattedCacheSize() async {
    final bytes = await getCacheSize();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Get number of cached images
  int get cachedImageCount {
    if (_imageMetaBox == null) return 0;
    // Subtract 1 for the version key
    return _imageMetaBox!.length > 0 ? _imageMetaBox!.length - 1 : 0;
  }
}
