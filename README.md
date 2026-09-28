# dart_webdav

A robust, resilient, and high-performance WebDAV client for Dart & Flutter, designed with enterprise-grade stability inspired by Cyberduck.

---

## ✨ Features

- **🛡️ Resilient URL & Path Encoding**: Idempotent path encoding that safely handles special characters (`#`, `+`, spaces, brackets, and multi-byte Unicode/Chinese paths) without double-encoding bugs.
- **⚡ Targeted PROPFIND Requests**: Generates explicit RFC 4918 `<d:propfind>` XML payloads requesting only necessary properties, cutting server response payload size by 50%+.
- **🔄 Auto-Retry with Exponential Backoff**: Built-in `WebDavRetryInterceptor` supporting 429 Too Many Requests, 503 Service Unavailable, connection resets, and honoring `Retry-After` headers.
- **🔍 Intelligent Server Probing & Auto-Detection**: Automatically tests connectivity and detects custom WebDAV entrypoints (AList `/dav`, Nextcloud `/remote.php/webdav`, Synology `/webdav`, etc.) on 404/405 errors.
- **📊 RFC 4331 Quota Support**: Native parsing of `quota-available-bytes` and `quota-used-bytes`.
- **🚀 Zero-Memory Streaming Upload**: `uploadFile` and `uploadStream` pipe file data directly via HTTP PUT without loading files into RAM, fully preventing OOM on huge files.
- **🕒 Timestamp Preservation & PROPPATCH**: RFC 4918 `proppatch` and `setLastModified` with automatic `X-OC-Mtime` support for Nextcloud/ownCloud.
- **⚡ Reactive Stream Directory Listing**: `listFilesStream` streams XML responses incrementally, delivering near-zero peak memory and instant UI rendering even for directories with 10,000+ items.
- **🎵 Media & Streaming Friendly**:
  - `downloadStream` with full HTTP Range request support (ideal for audio seeking and tag extraction like TagLib).
  - Built-in media type classification helpers (`isAudio`, `isImage`, `isLyric`).
- **🗂️ Full WebDAV Operations**: `listFiles`, `listFilesStream`, `getMetadata`, `downloadFile`, `uploadFile`, `uploadStream`, `uploadBytes`, `createDirectory` (`MKCOL`), `delete`, `move`, `copy`, `exists`, `proppatch`, `setLastModified`.
- **🧩 100% Pure Dart**: Fully cross-platform on Android, iOS, Windows, macOS, Linux, and Web.

---

## 🚀 Getting Started

Add `dart_webdav` to your `pubspec.yaml`:

```yaml
dependencies:
  dart_webdav:
    path: ./dart_webdav
```

---

## 📖 Usage Example

```dart
import 'dart:io';
import 'package:dart_webdav/dart_webdav.dart';

void main() async {
  // 1. Initialize client
  final client = WebDavClient.basic(
    baseUrl: 'https://nas.local:5006/dav',
    username: 'user',
    password: 'password',
    options: const WebDavClientOptions(
      maxRetries: 3,
      connectTimeout: Duration(seconds: 10),
      ignoreSsl: true, // For self-signed certs
    ),
  );

  // 2. Test connection & auto-detect path
  final test = await client.testConnection();
  if (!test.success) {
    print('Failed to connect: ${test.message}');
    return;
  }
  print('Connected: ${test.message}');

  // 3. Reactive Streaming Listing (Ideal for huge folders with thousands of tracks)
  await for (final file in client.listFilesStream('/Music/JayChou')) {
    print('${file.isDirectory ? "[DIR]" : "[FILE]"} ${file.name} (${file.contentLength} bytes)');
  }

  // 4. Zero-Memory Streaming File Upload with Timestamp Preservation
  final localSong = File('/path/to/Song.flac');
  await client.uploadFile(
    '/Music/JayChou/Song.flac',
    localSong,
    preserveTimestamp: true,
    onSendProgress: (sent, total) => print('Upload: ${(sent / total * 100).toStringAsFixed(1)}%'),
  );

  // 5. Check Storage Quota (RFC 4331)
  final quota = await client.getQuota();
  if (quota.totalBytes != null) {
    print('Used: ${quota.usedBytes} / Total: ${quota.totalBytes}');
  }
}
```

---

## 🏛️ Architecture & Cyberduck Design Patterns

| Design Pattern | How `dart_webdav` Implements It |
| :--- | :--- |
| **Namespace-tolerant XML Parser** | [PropFindXmlParser](lib/src/parser/propfind_xml_parser.dart) dynamically handles variable XML namespaces (`d:`, `D:`, `oc:`, default) and tolerates non-standard vendor XML. |
| **Reactive Chunked XML Streaming** | `listFilesStream` and `PropFindXmlParser.parseStream` parse `<response>` fragments on-the-fly, preventing memory bloat on 10,000+ files. |
| **Timestamp Preservation** | [PropPatchXmlBuilder](lib/src/parser/proppatch_xml_builder.dart) and `X-OC-Mtime` preserve original file modification times on upload. |
| **Zero-Memory Streaming Transfer** | `uploadFile` and `uploadStream` pipe streams directly to HTTP PUT with `Content-Length`. |
| **Exponential Backoff & Rate Limit** | [WebDavRetryInterceptor](lib/src/interceptors/webdav_retry_interceptor.dart) handles 429/503 responses and parses standard `Retry-After` headers. |
| **Safe Path Encoding** | [SafeUrlEncoder](lib/src/parser/safe_url_encoder.dart) provides idempotent RFC 3986 encoding to prevent broken URLs on non-ASCII & special symbols. |
| **IIS Compatibility** | Automatically injects `Translate: f` header to prevent IIS server-side script execution. |
