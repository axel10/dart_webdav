import 'package:dio/dio.dart';

import '../models/connection_result.dart';
import '../parser/propfind_xml_builder.dart';
import '../parser/safe_url_encoder.dart';

/// Probes and auto-detects WebDAV roots for popular servers (AList, Nextcloud, Synology, QNAP, TrueNAS).
class WebDavProbe {
  static const List<String> defaultCandidatePaths = [
    '/',
    '/dav',
    '/webdav',
    '/remote.php/webdav',
    '/remote.php/dav',
    '/dav/files',
  ];

  /// Tests connectivity and attempts to auto-detect valid WebDAV root paths if root returns 404/405.
  static Future<WebDavConnectionResult> testConnection({
    required Dio dio,
    required String baseUrl,
    String? explicitPath,
    Map<String, String>? authHeaders,
    List<String> candidatePaths = defaultCandidatePaths,
  }) async {
    final customPath = explicitPath?.trim();
    final hasExplicitPath =
        customPath != null && customPath.isNotEmpty && customPath != '/';
    final initialPath = hasExplicitPath ? customPath : '/';

    try {
      final initialStatus = await _probePath(
        dio: dio,
        baseUrl: baseUrl,
        path: initialPath,
        authHeaders: authHeaders,
      );

      if (initialStatus == 200 || initialStatus == 207) {
        return WebDavConnectionResult.success(
          message: 'WebDAV connected successfully',
          serverVersion: 'WebDAV (HTTP 207 Multi-Status)',
          detectedCustomPath: hasExplicitPath ? customPath : null,
          statusCode: initialStatus,
        );
      }

      if (initialStatus == 401) {
        return const WebDavConnectionResult.failure(
          '401 Unauthorized: Invalid username, password, or auth credentials',
          statusCode: 401,
        );
      }

      // If initial path gave 404/405 or was root, probe alternative paths
      if (!hasExplicitPath || initialStatus == 404 || initialStatus == 405) {
        for (final candidate in candidatePaths) {
          if (candidate == initialPath) continue;
          final status = await _probePath(
            dio: dio,
            baseUrl: baseUrl,
            path: candidate,
            authHeaders: authHeaders,
          );

          if (status == 200 || status == 207) {
            return WebDavConnectionResult.success(
              message: 'WebDAV connected successfully (Auto-detected: $candidate)',
              serverVersion: 'WebDAV (Auto-detected: $candidate)',
              detectedCustomPath: candidate,
              statusCode: status,
            );
          }
        }
      }

      if (initialStatus == 405) {
        return const WebDavConnectionResult.failure(
          '405 Method Not Allowed: Target path does not support WebDAV (e.g. AList requires /dav path).',
          statusCode: 405,
        );
      }

      if (initialStatus == 404) {
        return const WebDavConnectionResult.failure(
          '404 Not Found: Specified WebDAV path was not found on the server.',
          statusCode: 404,
        );
      }

      return WebDavConnectionResult.failure(
        'Server returned HTTP status $initialStatus',
        statusCode: initialStatus,
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 401) {
        return const WebDavConnectionResult.failure(
          '401 Unauthorized: Invalid WebDAV username or password',
          statusCode: 401,
        );
      }
      return WebDavConnectionResult.failure(
        'Connection failed: ${e.message ?? e.toString()}',
        statusCode: statusCode,
      );
    } catch (e) {
      return WebDavConnectionResult.failure('Error: $e');
    }
  }

  static Future<int?> _probePath({
    required Dio dio,
    required String baseUrl,
    required String path,
    Map<String, String>? authHeaders,
  }) async {
    try {
      final url = SafeUrlEncoder.buildUrl(
        baseUrl: baseUrl,
        relativePath: path,
      );

      final response = await dio.request<String>(
        url,
        data: PropFindXmlBuilder.build(properties: ['resourcetype']),
        options: Options(
          method: 'PROPFIND',
          headers: {
            ...?authHeaders,
            'Depth': '0',
            'Content-Type': 'application/xml; charset=utf-8',
          },
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null,
        ),
      );
      return response.statusCode;
    } catch (_) {
      return null;
    }
  }
}
