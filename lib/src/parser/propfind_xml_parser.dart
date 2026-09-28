import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../exceptions/webdav_exception.dart';
import '../models/webdav_file.dart';
import '../models/webdav_quota.dart';

/// Robust, namespace-tolerant parser for WebDAV 207 Multi-Status XML responses.
class PropFindXmlParser {
  /// Parses a stream of byte chunks into a stream of [WebDavFile]s with minimal memory footprint.
  ///
  /// Prevents OOM and frame drops on massive directories with tens of thousands of items.
  static Stream<WebDavFile> parseStream(
    Stream<List<int>> byteStream, {
    String? requestPath,
  }) async* {
    final cleanReqPath = _normalizePath(requestPath);
    var buffer = '';
    var isFirstNode = true;

    final regexResponse =
        RegExp(r'<([a-zA-Z0-9_\-]+:)?response[\s>]', caseSensitive: false);

    await for (final chunk in byteStream.transform(utf8.decoder)) {
      buffer += chunk;

      while (true) {
        final matchStart = regexResponse.firstMatch(buffer);
        if (matchStart == null) break;

        final prefix = matchStart.group(1) ?? '';
        final closeTag = '</${prefix}response>';
        final closeIdx = buffer
            .toLowerCase()
            .indexOf(closeTag.toLowerCase(), matchStart.start);

        if (closeIdx == -1) {
          // Waiting for subsequent chunks to complete this <response> element
          if (matchStart.start > 0) {
            buffer = buffer.substring(matchStart.start);
          }
          break;
        }

        final endIdx = closeIdx + closeTag.length;
        final responseXml = buffer.substring(matchStart.start, endIdx);
        buffer = buffer.substring(endIdx);

        try {
          final doc = XmlDocument.parse(responseXml);
          final file = _parseResponseNode(doc.rootElement);
          if (file != null) {
            final isSelf =
                cleanReqPath != null && _normalizePath(file.path) == cleanReqPath;
            if (isFirstNode && isSelf) {
              isFirstNode = false;
              continue;
            }
            isFirstNode = false;
            if (!isSelf) {
              yield file;
            }
          }
        } catch (_) {
          // Tolerant parser: skip malformed response chunk
        }
      }
    }
  }

  /// Parses a Multi-Status XML string into a list of [WebDavFile]s.
  static List<WebDavFile> parseFiles(String xmlString, {String? requestPath}) {
    if (xmlString.trim().isEmpty) return const [];

    final XmlDocument document;
    try {
      document = XmlDocument.parse(xmlString);
    } catch (e, st) {
      throw WebDavXmlParseException(
        'Failed to parse WebDAV Multi-Status XML response: $e',
        originalError: e,
        stackTrace: st,
      );
    }

    final responseNodes =
        document.findAllElements('response', namespace: '*').toList();
    if (responseNodes.isEmpty) return const [];

    final List<WebDavFile> results = [];
    final cleanReqPath = _normalizePath(requestPath);

    for (int i = 0; i < responseNodes.length; i++) {
      final resp = responseNodes[i];
      try {
        final file = _parseResponseNode(resp);
        if (file == null) continue;

        // Skip the parent directory itself in Depth: 1 listing
        if (responseNodes.length > 1 && i == 0) {
          // In standard RFC 4918 Depth: 1 responses, the 1st node is the target container
          continue;
        }

        if (cleanReqPath != null &&
            _normalizePath(file.path) == cleanReqPath) {
          continue;
        }

        results.add(file);
      } catch (_) {
        // Tolerant parser: skip invalid single item without failing the entire batch
        continue;
      }
    }

    return results;
  }

  /// Parses a single response element into a [WebDavFile].
  static WebDavFile? parseResponseElement(XmlElement resp) =>
      _parseResponseNode(resp);

  /// Parses storage quota from a 207 Multi-Status PROPFIND response (RFC 4331).
  static WebDavQuota parseQuota(String xmlString) {
    if (xmlString.trim().isEmpty) return const WebDavQuota();

    try {
      final document = XmlDocument.parse(xmlString);
      final responseNodes =
          document.findAllElements('response', namespace: '*').toList();
      if (responseNodes.isEmpty) return const WebDavQuota();

      for (final resp in responseNodes) {
        final propStats = resp.findElements('propstat', namespace: '*');
        for (final propstat in propStats) {
          final prop = propstat.findElements('prop', namespace: '*').firstOrNull;
          if (prop == null) continue;

          int? usedBytes;
          int? availableBytes;

          final usedEl = prop.findElements('quota-used-bytes', namespace: '*').firstOrNull ??
              prop.findElements('quotaused', namespace: '*').firstOrNull;
          if (usedEl != null) {
            usedBytes = int.tryParse(usedEl.innerText.trim());
          }

          final availEl = prop.findElements('quota-available-bytes', namespace: '*').firstOrNull ??
              prop.findElements('quota', namespace: '*').firstOrNull;
          if (availEl != null) {
            availableBytes = int.tryParse(availEl.innerText.trim());
          }

          if (usedBytes != null || availableBytes != null) {
            return WebDavQuota(
              usedBytes: usedBytes,
              availableBytes: availableBytes,
            );
          }
        }
      }
    } catch (_) {}

    return const WebDavQuota();
  }

  static WebDavFile? _parseResponseNode(XmlElement resp) {
    final hrefEl = resp.findElements('href', namespace: '*').firstOrNull;
    if (hrefEl == null) return null;

    final rawHref = hrefEl.innerText.trim();
    final cleanHref = _normalizeHref(rawHref);

    bool isDirectory = false;
    int contentLength = 0;
    DateTime? lastModified;
    DateTime? creationDate;
    String? contentType;
    String? etag;
    final Map<String, String> customProps = {};

    final propStats = resp.findElements('propstat', namespace: '*');
    for (final propStat in propStats) {
      final prop = propStat.findElements('prop', namespace: '*').firstOrNull;
      if (prop == null) continue;

      // 1. Check isDirectory
      final resType =
          prop.findElements('resourcetype', namespace: '*').firstOrNull;
      if (resType != null &&
          resType.findElements('collection', namespace: '*').isNotEmpty) {
        isDirectory = true;
      }

      // 2. Content Length
      final lenEl =
          prop.findElements('getcontentlength', namespace: '*').firstOrNull;
      if (lenEl != null) {
        contentLength = int.tryParse(lenEl.innerText.trim()) ?? 0;
      }

      // 3. Last Modified
      final modEl =
          prop.findElements('getlastmodified', namespace: '*').firstOrNull;
      if (modEl != null) {
        lastModified = _parseDate(modEl.innerText.trim());
      }

      // 4. Creation Date
      final createEl =
          prop.findElements('creationdate', namespace: '*').firstOrNull;
      if (createEl != null) {
        creationDate = _parseDate(createEl.innerText.trim());
      }

      // 5. Content Type
      final typeEl =
          prop.findElements('getcontenttype', namespace: '*').firstOrNull;
      if (typeEl != null) {
        contentType = typeEl.innerText.trim();
      }

      // 6. ETag
      final etagEl = prop.findElements('getetag', namespace: '*').firstOrNull;
      if (etagEl != null) {
        etag = etagEl.innerText.trim();
      }

      // 7. Extra/Custom Properties
      for (final child in prop.childElements) {
        final name = child.name.local;
        if (!const {
          'resourcetype',
          'getcontentlength',
          'getlastmodified',
          'creationdate',
          'getcontenttype',
          'getetag',
          'lockdiscovery',
          'supportedlock'
        }.contains(name)) {
          final val = child.innerText.trim();
          if (val.isNotEmpty) {
            customProps[name] = val;
          }
        }
      }
    }

    // Name resolution
    var name = p.basename(cleanHref);
    if (name.isEmpty) {
      name = cleanHref;
    }

    return WebDavFile(
      path: cleanHref.isEmpty ? '/' : cleanHref,
      name: name,
      isDirectory: isDirectory,
      contentLength: contentLength,
      lastModified: lastModified,
      creationDate: creationDate,
      contentType: contentType,
      etag: etag,
      customProperties: customProps,
    );
  }

  static String _normalizeHref(String rawHref) {
    var href = rawHref;
    try {
      href = Uri.decodeFull(rawHref);
    } catch (_) {}

    final schemeIdx = href.indexOf('://');
    if (schemeIdx > 0) {
      final pathStart = href.indexOf('/', schemeIdx + 3);
      href = pathStart >= 0 ? href.substring(pathStart) : '/';
    }

    href = href.replaceAll(RegExp(r'/+$'), '');
    if (!href.startsWith('/')) {
      href = '/$href';
    }
    return href;
  }

  static String? _normalizePath(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    var pStr = path.trim();
    try {
      pStr = Uri.decodeFull(pStr).trim();
    } catch (_) {}

    final schemeIdx = pStr.indexOf('://');
    if (schemeIdx > 0) {
      final pathStart = pStr.indexOf('/', schemeIdx + 3);
      pStr = pathStart >= 0 ? pStr.substring(pathStart) : '/';
    }

    pStr = pStr.replaceAll(RegExp(r'/+$'), '');
    if (pStr.isEmpty) return '/';
    return pStr.startsWith('/') ? pStr : '/$pStr';
  }

  static DateTime? _parseDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      return HttpDate.parse(dateStr);
    } catch (_) {}
    try {
      return DateTime.parse(dateStr);
    } catch (_) {}
    return null;
  }
}
