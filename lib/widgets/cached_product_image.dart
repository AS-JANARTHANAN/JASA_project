import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:JASA/services/image_cache_service.dart';

/// A widget that displays a cached product image with loading and error states
/// Uses local file storage for persistent caching - images load instantly after first download
class CachedProductImage extends StatefulWidget {
  final String? imageUrl;
  final String? imagePath; // The path in Supabase storage (for local cache lookup)
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CachedProductImage({
    super.key,
    this.imageUrl,
    this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<CachedProductImage> createState() => _CachedProductImageState();
}

class _CachedProductImageState extends State<CachedProductImage> {
  File? _localFile;
  bool _checkedCache = false;

  @override
  void initState() {
    super.initState();
    _checkLocalCache();
  }

  @override
  void didUpdateWidget(CachedProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl || oldWidget.imagePath != widget.imagePath) {
      _checkedCache = false;
      _checkLocalCache();
    }
  }

  void _checkLocalCache() {
    if (_checkedCache) return;
    _checkedCache = true;

    // Try to get from local cache using imagePath
    if (widget.imagePath != null) {
      try {
        final imageCacheService = ImageCacheService();
        if (imageCacheService.isInitialized) {
          final cachedFile = imageCacheService.getCachedImageFile(widget.imagePath!);
          if (cachedFile != null && cachedFile.existsSync()) {
            if (mounted) {
              setState(() => _localFile = cachedFile);
            }
            return;
          }
        }
      } catch (e) {
        // Ignore errors, fall back to network
        debugPrint('Cache check error: $e');
      }
    }

    // Not in cache, will use network fallback
    if (mounted) {
      setState(() => _localFile = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // No image URL provided
    if (widget.imageUrl == null && widget.imagePath == null) {
      return _buildPlaceholder(theme);
    }

    Widget imageWidget;

    // Use local file if available (instant loading!)
    if (_localFile != null) {
      imageWidget = Image.file(
        _localFile!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: widget.width != null ? (widget.width! * 2).toInt() : null,
        cacheHeight: widget.height != null ? (widget.height! * 2).toInt() : null,
        errorBuilder: (context, error, stackTrace) => _buildErrorWidget(theme),
      );
    }
    // Fall back to network image with caching
    else if (widget.imageUrl != null) {
      imageWidget = CachedNetworkImage(
        imageUrl: widget.imageUrl!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        memCacheWidth: widget.width != null ? (widget.width! * 2).toInt() : null,
        memCacheHeight: widget.height != null ? (widget.height! * 2).toInt() : null,
        fadeInDuration: const Duration(milliseconds: 150),
        fadeOutDuration: const Duration(milliseconds: 100),
        cacheKey: widget.imagePath ?? widget.imageUrl,
        maxWidthDiskCache: 800,
        maxHeightDiskCache: 800,
        placeholder: (context, url) => widget.placeholder ?? _buildLoadingWidget(theme),
        errorWidget: (context, url, error) => widget.errorWidget ?? _buildErrorWidget(theme),
      );
    } else {
      return _buildPlaceholder(theme);
    }

    if (widget.borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: widget.borderRadius,
      ),
      child: Icon(
        Icons.image_outlined,
        size: (widget.width ?? 50) * 0.5,
        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
      ),
    );
  }

  Widget _buildLoadingWidget(ThemeData theme) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: widget.borderRadius,
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(ThemeData theme) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withOpacity(0.3),
        borderRadius: widget.borderRadius,
      ),
      child: Icon(
        Icons.broken_image_outlined,
        size: (widget.width ?? 50) * 0.4,
        color: theme.colorScheme.error.withOpacity(0.5),
      ),
    );
  }
}

/// A widget that displays a circular cached product image (for avatars)
class CachedProductAvatar extends StatefulWidget {
  final String? imageUrl;
  final String? imagePath;
  final double radius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CachedProductAvatar({
    super.key,
    this.imageUrl,
    this.imagePath,
    this.radius = 24,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<CachedProductAvatar> createState() => _CachedProductAvatarState();
}

class _CachedProductAvatarState extends State<CachedProductAvatar> {
  File? _localFile;

  @override
  void initState() {
    super.initState();
    _checkLocalCache();
  }

  @override
  void didUpdateWidget(CachedProductAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _checkLocalCache();
    }
  }

  void _checkLocalCache() {
    if (widget.imagePath != null) {
      try {
        final imageCacheService = ImageCacheService();
        if (imageCacheService.isInitialized) {
          final cachedFile = imageCacheService.getCachedImageFile(widget.imagePath!);
          if (cachedFile != null && cachedFile.existsSync()) {
            if (mounted) {
              setState(() => _localFile = cachedFile);
            }
            return;
          }
        }
      } catch (e) {
        debugPrint('Cache check error: $e');
      }
    }
    if (mounted) {
      setState(() => _localFile = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.imageUrl == null && widget.imagePath == null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.image_outlined,
          size: widget.radius,
          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
        ),
      );
    }

    // Use local file if available
    if (_localFile != null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundImage: FileImage(_localFile!),
      );
    }

    // Fall back to network image
    if (widget.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl!,
        cacheKey: widget.imagePath ?? widget.imageUrl,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: widget.radius,
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) =>
            widget.placeholder ??
            CircleAvatar(
              radius: widget.radius,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: SizedBox(
                width: widget.radius,
                height: widget.radius,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary.withOpacity(0.5),
                ),
              ),
            ),
        errorWidget: (context, url, error) =>
            widget.errorWidget ??
            CircleAvatar(
              radius: widget.radius,
              backgroundColor: theme.colorScheme.errorContainer,
              child: Icon(
                Icons.broken_image_outlined,
                size: widget.radius,
                color: theme.colorScheme.error.withOpacity(0.5),
              ),
            ),
      );
    }

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
    );
  }
}
