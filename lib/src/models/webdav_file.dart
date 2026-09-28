import 'package:path/path.dart' as p;

/// Represents a WebDAV remote resource (file or collection).
class WebDavFile {
  /// Normalized absolute remote path (e.g. `/music/album/song.flac`).
  final String path;

  /// File or folder name (e.g. `song.flac`).
  final String name;

  /// Whether this resource is a WebDAV collection (`<d:collection/>`).
  final bool isDirectory;

  /// Size in bytes (`<d:getcontentlength>`). 0 for directories.
  final int contentLength;

  /// Last modification timestamp (`<d:getlastmodified>`).
  final DateTime? lastModified;

  /// Creation timestamp (`<d:creationdate>`).
  final DateTime? creationDate;

  /// HTTP Content-Type (`<d:getcontenttype>`), e.g. `audio/flac`.
  final String? contentType;

  /// Entity tag (`<d:getetag>`) for caching and conditional requests.
  final String? etag;

  /// Additional custom or extended properties parsed from PROPFIND propstat.
  final Map<String, String> customProperties;

  const WebDavFile({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.contentLength,
    this.lastModified,
    this.creationDate,
    this.contentType,
    this.etag,
    this.customProperties = const {},
  });

  /// True if the file extension matches common audio formats.
  bool get isAudio {
    if (isDirectory) return false;
    if (p.basename(name).startsWith('._')) return false;
    final ext = p.extension(name).toLowerCase();
    return const {
      '.mp3',
      '.flac',
      '.wav',
      '.aac',
      '.m4a',
      '.ogg',
      '.opus',
      '.ape',
      '.dsf',
      '.dff',
      '.wma',
      '.alac',
      '.aif',
      '.aiff',
      '.wv',
      '.caf',
      '.m4b',
      '.m4p',
      '.mid',
      '.midi',
      '.webm',
    }.contains(ext);
  }

  /// True if the file extension matches common image formats.
  bool get isImage {
    if (isDirectory) return false;
    final ext = p.extension(name).toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'}.contains(ext);
  }

  /// True if the file extension is a lyric format (`.lrc`).
  bool get isLyric {
    if (isDirectory) return false;
    final ext = p.extension(name).toLowerCase();
    return ext == '.lrc';
  }

  WebDavFile copyWith({
    String? path,
    String? name,
    bool? isDirectory,
    int? contentLength,
    DateTime? lastModified,
    DateTime? creationDate,
    String? contentType,
    String? etag,
    Map<String, String>? customProperties,
  }) {
    return WebDavFile(
      path: path ?? this.path,
      name: name ?? this.name,
      isDirectory: isDirectory ?? this.isDirectory,
      contentLength: contentLength ?? this.contentLength,
      lastModified: lastModified ?? this.lastModified,
      creationDate: creationDate ?? this.creationDate,
      contentType: contentType ?? this.contentType,
      etag: etag ?? this.etag,
      customProperties: customProperties ?? this.customProperties,
    );
  }

  @override
  String toString() =>
      'WebDavFile(name: $name, path: $path, isDir: $isDirectory, size: $contentLength, mtime: $lastModified)';
}
