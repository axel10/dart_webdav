/// Builder for standard RFC 4918 / RFC 4331 PROPFIND XML request payloads.
class PropFindXmlBuilder {
  /// Standard properties needed for file listing and metadata extraction.
  static const List<String> standardProperties = [
    'resourcetype',
    'getcontentlength',
    'getlastmodified',
    'creationdate',
    'getcontenttype',
    'getetag',
    'displayname',
  ];

  /// Standard properties including storage quota (RFC 4331).
  static const List<String> quotaProperties = [
    'quota-available-bytes',
    'quota-used-bytes',
    'quota',
    'quotaused',
  ];

  /// Builds a PROPFIND XML payload requesting specific DAV properties.
  static String build({
    List<String>? properties,
    bool includeQuota = false,
  }) {
    final props = <String>{
      ...?properties,
      if (properties == null) ...standardProperties,
      if (includeQuota) ...quotaProperties,
    };

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8" ?>');
    buffer.writeln('<d:propfind xmlns:d="DAV:">');
    buffer.writeln('  <d:prop>');
    for (final prop in props) {
      buffer.writeln('    <d:$prop/>');
    }
    buffer.writeln('  </d:prop>');
    buffer.writeln('</d:propfind>');
    return buffer.toString();
  }

  /// Builds an allprop PROPFIND XML request body.
  static String buildAllProp() {
    return '<?xml version="1.0" encoding="utf-8" ?>\n'
        '<d:propfind xmlns:d="DAV:">\n'
        '  <d:allprop/>\n'
        '</d:propfind>';
  }
}
