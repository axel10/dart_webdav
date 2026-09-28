import 'dart:io';

/// Builder for standard RFC 4918 PROPPATCH XML request payloads.
///
/// Used for updating remote file metadata, custom properties, and preserving modification timestamps.
class PropPatchXmlBuilder {
  /// Builds a PROPPATCH XML body to set custom properties and/or remove properties.
  static String build({
    Map<String, String>? setProperties,
    List<String>? removeProperties,
    String? customNamespaceUri,
    String? customPrefix,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8" ?>');

    final nsAttr = customNamespaceUri != null && customPrefix != null
        ? ' xmlns:$customPrefix="$customNamespaceUri"'
        : '';

    buffer.writeln('<d:propertyupdate xmlns:d="DAV:"$nsAttr>');

    // <d:set>
    if (setProperties != null && setProperties.isNotEmpty) {
      buffer.writeln('  <d:set>');
      buffer.writeln('    <d:prop>');
      for (final entry in setProperties.entries) {
        final key = entry.key;
        final value = _escapeXml(entry.value);
        if (key.contains(':')) {
          buffer.writeln('      <$key>$value</$key>');
        } else if (customPrefix != null) {
          buffer.writeln('      <$customPrefix:$key>$value</$customPrefix:$key>');
        } else {
          buffer.writeln('      <d:$key>$value</d:$key>');
        }
      }
      buffer.writeln('    </d:prop>');
      buffer.writeln('  </d:set>');
    }

    // <d:remove>
    if (removeProperties != null && removeProperties.isNotEmpty) {
      buffer.writeln('  <d:remove>');
      buffer.writeln('    <d:prop>');
      for (final prop in removeProperties) {
        if (prop.contains(':')) {
          buffer.writeln('      <$prop/>');
        } else if (customPrefix != null) {
          buffer.writeln('      <$customPrefix:$prop/>');
        } else {
          buffer.writeln('      <d:$prop/>');
        }
      }
      buffer.writeln('    </d:prop>');
      buffer.writeln('  </d:remove>');
    }

    buffer.writeln('</d:propertyupdate>');
    return buffer.toString();
  }

  /// Builds a PROPPATCH body to set the file modification time (`getlastmodified`).
  static String buildLastModified(DateTime lastModified) {
    final utc = lastModified.toUtc();
    final rfc1123 = HttpDate.format(utc);
    return build(
      setProperties: {
        'getlastmodified': rfc1123,
      },
    );
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
