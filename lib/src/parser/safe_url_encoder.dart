/// Utility class for idempotent, robust URL and Path encoding according to RFC 3986.
///
/// Prevents common WebDAV path bugs caused by double encoding or special characters
/// like `#`, `+`, spaces, brackets, and non-ASCII Chinese/Unicode characters.
class SafeUrlEncoder {
  /// Safely encodes a relative or absolute path segment-by-segment.
  /// Idempotent (does not double-encode already percent-encoded strings).
  static String encodePath(String path) {
    if (path.isEmpty) return path;
    final isAbsolute = path.startsWith('/');
    final endsWithSlash = path.length > 1 && path.endsWith('/');

    final rawSegments = path.split('/');
    final encodedSegments = <String>[];

    for (final seg in rawSegments) {
      if (seg.isEmpty) continue;
      try {
        final decoded = Uri.decodeComponent(seg);
        encodedSegments.add(Uri.encodeComponent(decoded));
      } catch (_) {
        encodedSegments.add(Uri.encodeComponent(seg));
      }
    }

    var result = encodedSegments.join('/');
    if (isAbsolute) {
      result = '/$result';
    }
    if (endsWithSlash && !result.endsWith('/')) {
      result = '$result/';
    }
    return result.isEmpty ? '/' : result;
  }

  /// Normalizes and encodes a full URL safely, preserving query parameters and origin.
  static String encodeUrl(String url) {
    if (url.isEmpty) return url;
    try {
      final schemeEnd = url.indexOf('://');
      if (schemeEnd > 0) {
        final scheme = url.substring(0, schemeEnd);
        final rest = url.substring(schemeEnd + 3);
        final pathStart = rest.indexOf('/');
        if (pathStart >= 0) {
          final hostPart = rest.substring(0, pathStart);
          final rawPath = rest.substring(pathStart);
          final queryIdx = rawPath.indexOf('?');
          if (queryIdx >= 0) {
            final pathOnly = rawPath.substring(0, queryIdx);
            final queryPart = rawPath.substring(queryIdx);
            return '$scheme://$hostPart${encodePath(pathOnly)}$queryPart';
          }
          return '$scheme://$hostPart${encodePath(rawPath)}';
        }
        return '$scheme://$rest';
      }
      return encodePath(url);
    } catch (_) {
      try {
        final decoded = Uri.decodeFull(url);
        return Uri.encodeFull(decoded);
      } catch (_) {
        return url;
      }
    }
  }

  /// Combines a base URL with a relative path safely.
  static String buildUrl({
    required String baseUrl,
    required String relativePath,
    String? username,
    String? password,
    bool includeAuth = false,
  }) {
    var base = baseUrl.trim();
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'http://$base';
    }
    base = base.replaceAll(RegExp(r'/+$'), '');

    var path = relativePath.trim();
    if (!path.startsWith('/')) {
      path = '/$path';
    }

    final parsedBase = Uri.tryParse(base) ?? Uri.tryParse(Uri.encodeFull(base));
    String rawUrl;

    if (parsedBase != null) {
      final authPrefix = includeAuth && username != null && username.isNotEmpty
          ? '${Uri.encodeComponent(username)}${password != null && password.isNotEmpty ? ':${Uri.encodeComponent(password)}' : ''}@'
          : '';
      final origin =
          '${parsedBase.scheme}://$authPrefix${parsedBase.host}${parsedBase.hasPort ? ':${parsedBase.port}' : ''}';

      if (parsedBase.path.isNotEmpty && parsedBase.path != '/') {
        final basePath = parsedBase.path.replaceAll(RegExp(r'/+$'), '');
        if (path == basePath || path.startsWith('$basePath/')) {
          rawUrl = '$origin$path';
        } else {
          rawUrl = '$origin$basePath$path';
        }
      } else {
        rawUrl = '$origin$path';
      }
    } else {
      rawUrl = '$base$path';
    }

    return encodeUrl(rawUrl);
  }
}
