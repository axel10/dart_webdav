import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../auth/webdav_auth.dart';
import '../exceptions/webdav_exception.dart';
import '../interceptors/webdav_retry_interceptor.dart';
import '../models/connection_result.dart';
import '../models/webdav_file.dart';
import '../models/webdav_options.dart';
import '../models/webdav_quota.dart';
import '../parser/propfind_xml_builder.dart';
import '../parser/propfind_xml_parser.dart';
import '../parser/proppatch_xml_builder.dart';
import '../parser/safe_url_encoder.dart';
import 'webdav_probe.dart';

/// Comprehensive, resilient WebDAV client implementing RFC 4918 and RFC 4331.
class WebDavClient {
  final String baseUrl;
  final WebDavAuth auth;
  final WebDavClientOptions options;
  late final Dio _dio;

  WebDavClient({
    required this.baseUrl,
    this.auth = const WebDavAnonymousAuth(),
    this.options = const WebDavClientOptions(),
    Dio? customDio,
  }) {
    _dio = customDio ??
        Dio(
          BaseOptions(
            connectTimeout: options.connectTimeout,
            receiveTimeout: options.receiveTimeout,
            sendTimeout: options.sendTimeout,
            headers: {
              'User-Agent': options.userAgent,
              if (options.enableIisTranslateHeader) 'Translate': 'f',
              ...options.extraHeaders,
            },
          ),
        );

    // SSL certificate bypass for self-signed certificates (if configured)
    if (options.ignoreSsl && customDio == null) {
      final adapter = _dio.httpClientAdapter;
      if (adapter is IOHttpClientAdapter) {
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        };
      }
    }

    // Add Retry Interceptor (Exponential backoff, 429/503 rate limit & network retry)
    if (options.maxRetries > 0 && customDio == null) {
      _dio.interceptors.add(
        WebDavRetryInterceptor(
          dio: _dio,
          maxRetries: options.maxRetries,
          initialDelay: options.initialRetryDelay,
          maxDelay: options.maxRetryDelay,
        ),
      );
    }
  }

  /// Convenience constructor for username/password Basic Auth.
  factory WebDavClient.basic({
    required String baseUrl,
    required String username,
    required String password,
    WebDavClientOptions options = const WebDavClientOptions(),
    Dio? customDio,
  }) {
    return WebDavClient(
      baseUrl: baseUrl,
      auth: WebDavBasicAuth(username: username, password: password),
      options: options,
      customDio: customDio,
    );
  }

  /// Returns standard authentication headers.
  Map<String, String> get authHeaders =>
      auth.getHeaders('PROPFIND', baseUrl);

  /// Builds a fully-qualified, safe percent-encoded URL for the given relative path.
  String buildFullUrl(String relativePath, {bool includeAuth = false}) {
    final (u, p) = auth is WebDavBasicAuth
        ? ((auth as WebDavBasicAuth).username, (auth as WebDavBasicAuth).password)
        : (null, null);

    return SafeUrlEncoder.buildUrl(
      baseUrl: baseUrl,
      relativePath: relativePath,
      username: u,
      password: p,
      includeAuth: includeAuth,
    );
  }

  /// Builds a playable stream URL with inline authentication credentials.
  String buildStreamUrl(String relativePath) =>
      buildFullUrl(relativePath, includeAuth: true);

  /// Tests connectivity and auto-detects root directory if applicable.
  Future<WebDavConnectionResult> testConnection({String? explicitPath}) {
    return WebDavProbe.testConnection(
      dio: _dio,
      baseUrl: baseUrl,
      explicitPath: explicitPath,
      authHeaders: authHeaders,
    );
  }

  /// Lists files and sub-folders in [path] using PROPFIND with `Depth: 1`.
  Future<List<WebDavFile>> listFiles(
    String path, {
    int depth = 1,
    List<String>? requestedProperties,
    CancelToken? cancelToken,
  }) async {
    final url = buildFullUrl(path);
    final payload = PropFindXmlBuilder.build(properties: requestedProperties);

    try {
      final response = await _dio.request<String>(
        url,
        data: payload,
        cancelToken: cancelToken,
        options: Options(
          method: 'PROPFIND',
          headers: {
            ...authHeaders,
            'Depth': depth.toString(),
            'Content-Type': 'application/xml; charset=utf-8',
          },
          responseType: ResponseType.plain,
        ),
      );

      final rawXml = response.data;
      if (rawXml == null || rawXml.isEmpty) return const [];

      return PropFindXmlParser.parseFiles(rawXml, requestPath: path);
    } on DioException catch (e) {
      throw WebDavException.fromDio(e, path: path);
    }
  }

  /// Lists files and sub-folders in [path] using PROPFIND as a reactive [Stream].
  ///
  /// Parses incoming XML packets progressively, cutting peak memory to near zero
  /// and enabling immediate rendering for massive directories containing 10,000+ files.
  Stream<WebDavFile> listFilesStream(
    String path, {
    int depth = 1,
    List<String>? requestedProperties,
    CancelToken? cancelToken,
  }) async* {
    final url = buildFullUrl(path);
    final payload = PropFindXmlBuilder.build(properties: requestedProperties);

    try {
      final response = await _dio.request<ResponseBody>(
        url,
        data: payload,
        cancelToken: cancelToken,
        options: Options(
          method: 'PROPFIND',
          headers: {
            ...authHeaders,
            'Depth': depth.toString(),
            'Content-Type': 'application/xml; charset=utf-8',
          },
          responseType: ResponseType.stream,
        ),
      );

      final body = response.data;
      if (body == null) return;

      yield* PropFindXmlParser.parseStream(body.stream, requestPath: path);
    } on DioException catch (e) {
      throw WebDavException.fromDio(e, path: path);
    }
  }

  /// Fetches metadata for a single remote resource using PROPFIND with `Depth: 0`.
  Future<WebDavFile?> getMetadata(
    String path, {
    List<String>? requestedProperties,
    CancelToken? cancelToken,
  }) async {
    final files = await listFiles(
      path,
      depth: 0,
      requestedProperties: requestedProperties,
      cancelToken: cancelToken,
    );
    return files.firstOrNull;
  }

  /// Queries storage quota for the user or directory (RFC 4331).
  Future<WebDavQuota> getQuota([String path = '/']) async {
    final url = buildFullUrl(path);
    final payload = PropFindXmlBuilder.build(
      properties: PropFindXmlBuilder.quotaProperties,
      includeQuota: true,
    );

    try {
      final response = await _dio.request<String>(
        url,
        data: payload,
        options: Options(
          method: 'PROPFIND',
          headers: {
            ...authHeaders,
            'Depth': '0',
            'Content-Type': 'application/xml; charset=utf-8',
          },
          responseType: ResponseType.plain,
        ),
      );

      final rawXml = response.data;
      if (rawXml == null || rawXml.isEmpty) return const WebDavQuota();

      return PropFindXmlParser.parseQuota(rawXml);
    } catch (_) {
      return const WebDavQuota();
    }
  }

  /// Downloads file content as text (e.g. `.lrc` lyrics or text configs).
  Future<String?> getText(String path, {CancelToken? cancelToken}) async {
    final url = buildFullUrl(path);
    try {
      final response = await _dio.get<String>(
        url,
        cancelToken: cancelToken,
        options: Options(
          headers: authHeaders,
          responseType: ResponseType.plain,
        ),
      );
      return response.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw WebDavException.fromDio(e, path: path);
    }
  }

  /// Downloads a remote file to a local destination path with progress callbacks.
  Future<void> downloadFile(
    String remotePath,
    String localSavePath, {
    ProgressCallback? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    final url = buildFullUrl(remotePath);
    try {
      await _dio.download(
        url,
        localSavePath,
        onReceiveProgress: onReceiveProgress,
        cancelToken: cancelToken,
        options: Options(headers: authHeaders),
      );
    } on DioException catch (e) {
      throw WebDavException.fromDio(e, path: remotePath);
    }
  }

  /// Opens an HTTP Range stream for the remote file (ideal for media streaming & TagLib probing).
  Future<ResponseBody> downloadStream(
    String remotePath, {
    int? startByte,
    int? endByte,
    CancelToken? cancelToken,
  }) async {
    final url = buildFullUrl(remotePath);
    final headers = <String, String>{...authHeaders};

    if (startByte != null || endByte != null) {
      final start = startByte ?? 0;
      final end = endByte != null ? endByte.toString() : '';
      headers['Range'] = 'bytes=$start-$end';
    }

    try {
      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
        ),
      );
      final body = response.data;
      if (body == null) {
        throw WebDavException('Empty stream response received', path: remotePath);
      }
      return body;
    } on DioException catch (e) {
      throw WebDavException.fromDio(e, path: remotePath);
    }
  }

  /// Uploads local file bytes to remote WebDAV path.
  Future<void> uploadBytes(
    String remotePath,
    Uint8List bytes, {
    String? contentType,
    DateTime? lastModified,
    bool preserveTimestamp = false,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    await uploadStream(
      remotePath,
      Stream.fromIterable([bytes]),
      bytes.length,
      contentType: contentType,
      lastModified: lastModified,
      preserveTimestamp: preserveTimestamp,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  /// Uploads a local file directly as a stream without holding the file in memory.
  ///
  /// Prevents Out-Of-Memory (OOM) errors on large media albums, FLAC files, and backups.
  Future<void> uploadFile(
    String remotePath,
    File localFile, {
    String? contentType,
    DateTime? lastModified,
    bool preserveTimestamp = false,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final length = await localFile.length();
    final mtime = lastModified ??
        (preserveTimestamp ? await localFile.lastModified() : null);
    await uploadStream(
      remotePath,
      localFile.openRead(),
      length,
      contentType: contentType,
      lastModified: mtime,
      preserveTimestamp: preserveTimestamp,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  /// Uploads an arbitrary binary stream directly to remote WebDAV path via HTTP PUT.
  Future<void> uploadStream(
    String remotePath,
    Stream<List<int>> stream,
    int contentLength, {
    String? contentType,
    DateTime? lastModified,
    bool preserveTimestamp = false,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final url = buildFullUrl(remotePath);
    final headers = <String, String>{
      ...authHeaders,
      'Content-Length': contentLength.toString(),
      if (contentType != null) 'Content-Type': contentType,
      if (lastModified != null)
        'X-OC-Mtime': (lastModified.millisecondsSinceEpoch ~/ 1000).toString(),
    };

    try {
      await _dio.put(
        url,
        data: stream,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        options: Options(headers: headers),
      );

      // Attempt RFC 4918 PROPPATCH if preserveTimestamp is enabled
      if (lastModified != null && preserveTimestamp) {
        try {
          await setLastModified(remotePath, lastModified, cancelToken: cancelToken);
        } catch (_) {
          // Non-blocking fallback for servers not supporting PROPPATCH
        }
      }
    } on DioException catch (e) {
      throw WebDavException.fromDio(e, path: remotePath);
    }
  }

  /// Updates or removes remote WebDAV properties using RFC 4918 `PROPPATCH`.
  Future<void> proppatch(
    String remotePath, {
    Map<String, String>? setProperties,
    List<String>? removeProperties,
    String? customNamespaceUri,
    String? customPrefix,
    CancelToken? cancelToken,
  }) async {
    final url = buildFullUrl(remotePath);
    final payload = PropPatchXmlBuilder.build(
      setProperties: setProperties,
      removeProperties: removeProperties,
      customNamespaceUri: customNamespaceUri,
      customPrefix: customPrefix,
    );

    try {
      await _dio.request(
        url,
        data: payload,
        cancelToken: cancelToken,
        options: Options(
          method: 'PROPPATCH',
          headers: {
            ...authHeaders,
            'Content-Type': 'application/xml; charset=utf-8',
          },
        ),
      );
    } on DioException catch (e) {
      throw WebDavException.fromDio(e, path: remotePath);
    }
  }

  /// Preserves or updates the last modified timestamp of a remote resource using `PROPPATCH`.
  Future<void> setLastModified(
    String remotePath,
    DateTime lastModified, {
    CancelToken? cancelToken,
  }) async {
    final url = buildFullUrl(remotePath);
    final payload = PropPatchXmlBuilder.buildLastModified(lastModified);

    try {
      await _dio.request(
        url,
        data: payload,
        cancelToken: cancelToken,
        options: Options(
          method: 'PROPPATCH',
          headers: {
            ...authHeaders,
            'Content-Type': 'application/xml; charset=utf-8',
          },
        ),
      );
    } on DioException catch (e) {
      throw WebDavException.fromDio(e, path: remotePath);
    }
  }

  /// Creates a remote directory using `MKCOL`.
  Future<void> createDirectory(String remotePath, {CancelToken? cancelToken}) async {
    final url = buildFullUrl(remotePath);
    try {
      await _dio.request(
        url,
        cancelToken: cancelToken,
        options: Options(
          method: 'MKCOL',
          headers: authHeaders,
        ),
      );
    } on DioException catch (e) {
      throw WebDavException.fromDio(e, path: remotePath);
    }
  }

  /// Deletes a file or directory using `DELETE`.
  Future<void> delete(String remotePath, {CancelToken? cancelToken}) async {
    final url = buildFullUrl(remotePath);
    try {
      await _dio.delete(
        url,
        cancelToken: cancelToken,
        options: Options(headers: authHeaders),
      );
    } on DioException catch (e) {
      throw WebDavException.fromDio(e, path: remotePath);
    }
  }

  /// Moves or renames a remote file/folder using `MOVE`.
  Future<void> move(
    String fromPath,
    String toPath, {
    bool overwrite = false,
    CancelToken? cancelToken,
  }) async {
    final sourceUrl = buildFullUrl(fromPath);
    final destinationUrl = buildFullUrl(toPath);

    try {
      await _dio.request(
        sourceUrl,
        cancelToken: cancelToken,
        options: Options(
          method: 'MOVE',
          headers: {
            ...authHeaders,
            'Destination': destinationUrl,
            'Overwrite': overwrite ? 'T' : 'F',
          },
        ),
      );
    } on DioException catch (e) {
      throw WebDavException.fromDio(e, path: fromPath);
    }
  }

  /// Copies a remote file/folder using `COPY`.
  Future<void> copy(
    String fromPath,
    String toPath, {
    bool overwrite = false,
    CancelToken? cancelToken,
  }) async {
    final sourceUrl = buildFullUrl(fromPath);
    final destinationUrl = buildFullUrl(toPath);

    try {
      await _dio.request(
        sourceUrl,
        cancelToken: cancelToken,
        options: Options(
          method: 'COPY',
          headers: {
            ...authHeaders,
            'Destination': destinationUrl,
            'Overwrite': overwrite ? 'T' : 'F',
          },
        ),
      );
    } on DioException catch (e) {
      throw WebDavException.fromDio(e, path: fromPath);
    }
  }

  /// Checks if a remote file or folder exists.
  Future<bool> exists(String remotePath, {CancelToken? cancelToken}) async {
    final url = buildFullUrl(remotePath);
    try {
      final response = await _dio.head(
        url,
        cancelToken: cancelToken,
        options: Options(
          headers: authHeaders,
          validateStatus: (status) => status != null,
        ),
      );
      if (response.statusCode == 200 || response.statusCode == 207) {
        return true;
      }
    } catch (_) {}

    try {
      final meta = await getMetadata(remotePath, cancelToken: cancelToken);
      return meta != null;
    } catch (_) {
      return false;
    }
  }
}
