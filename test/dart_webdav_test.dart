import 'package:flutter_test/flutter_test.dart';
import 'package:dart_webdav/dart_webdav.dart';

void main() {
  group('SafeUrlEncoder Tests', () {
    test('Encodes special characters and Chinese paths safely', () {
      const path = '/音乐库/周杰伦/叶惠美 #1 + 晴天 [2003].flac';
      final encoded = SafeUrlEncoder.encodePath(path);

      expect(encoded, isNot(contains(' ')));
      expect(encoded, isNot(contains('#')));
      expect(encoded, isNot(contains('[')));
      expect(encoded, isNot(contains(']')));
      expect(encoded, contains('%20'));
      expect(encoded, contains('%23'));
      expect(encoded, contains('%2B'));

      // Idempotent: double encoding produces the exact same output
      final doubleEncoded = SafeUrlEncoder.encodePath(encoded);
      expect(doubleEncoded, equals(encoded));
    });

    test('buildUrl handles origin, auth, and subpaths correctly', () {
      final url = SafeUrlEncoder.buildUrl(
        baseUrl: 'http://nas.local:5005/dav',
        relativePath: '/周杰伦/晴天.mp3',
        username: 'admin',
        password: 'password@123',
        includeAuth: true,
      );

      expect(url, startsWith('http://admin:password%40123@nas.local:5005/dav/%E5%91%A8%E6%9D%B0%E4%BC%A6/%E6%99%B4%E5%A4%A9.mp3'));
    });
  });

  group('PropFindXmlBuilder & PropFindXmlParser Tests', () {
    test('Builds valid RFC 4918 XML propfind body', () {
      final xml = PropFindXmlBuilder.build(includeQuota: true);
      expect(xml, contains('<d:propfind xmlns:d="DAV:">'));
      expect(xml, contains('<d:getcontentlength/>'));
      expect(xml, contains('<d:quota-available-bytes/>'));
    });

    test('Parses RFC 4918 Multi-Status XML response and skips parent', () {
      const mockXml = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/music/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/music/Jay%20Chou/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
        <d:getlastmodified>Sun, 06 Nov 1994 08:49:37 GMT</d:getlastmodified>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/music/Track01.flac</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
        <d:getcontentlength>34567890</d:getcontentlength>
        <d:getlastmodified>Mon, 15 Jan 2024 12:00:00 GMT</d:getlastmodified>
        <d:getcontenttype>audio/flac</d:getcontenttype>
        <d:getetag>"123456-abc"</d:getetag>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

      final files = PropFindXmlParser.parseFiles(mockXml, requestPath: '/music');
      expect(files.length, equals(2));

      final dir = files[0];
      expect(dir.name, equals('Jay Chou'));
      expect(dir.isDirectory, isTrue);

      final audio = files[1];
      expect(audio.name, equals('Track01.flac'));
      expect(audio.isDirectory, isFalse);
      expect(audio.isAudio, isTrue);
      expect(audio.contentLength, equals(34567890));
      expect(audio.contentType, equals('audio/flac'));
      expect(audio.etag, equals('"123456-abc"'));
    });

    test('Parses RFC 4331 Quota properties', () {
      const mockQuotaXml = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/</d:href>
    <d:propstat>
      <d:prop>
        <d:quota-available-bytes>50000000000</d:quota-available-bytes>
        <d:quota-used-bytes>15000000000</d:quota-used-bytes>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

      final quota = PropFindXmlParser.parseQuota(mockQuotaXml);
      expect(quota.availableBytes, equals(50000000000));
      expect(quota.usedBytes, equals(15000000000));
      expect(quota.totalBytes, equals(65000000000));
      expect(quota.usageRatio, closeTo(15 / 65, 0.01));
    });
  });

  group('WebDavFile Media Extensions Tests', () {
    test('Correctly identifies audio, image, and lyrics', () {
      const audio = WebDavFile(
        path: '/test.flac',
        name: 'test.flac',
        isDirectory: false,
        contentLength: 100,
      );
      expect(audio.isAudio, isTrue);
      expect(audio.isImage, isFalse);
      expect(audio.isLyric, isFalse);

      const lrc = WebDavFile(
        path: '/test.lrc',
        name: 'test.lrc',
        isDirectory: false,
        contentLength: 50,
      );
      expect(lrc.isAudio, isFalse);
      expect(lrc.isLyric, isTrue);
    });
  });

  group('PropPatchXmlBuilder Tests', () {
    test('Generates RFC 4918 PROPPATCH XML payload for set and remove', () {
      final xml = PropPatchXmlBuilder.build(
        setProperties: {'author': 'Jay Chou', 'genre': 'Pop & Rock'},
        removeProperties: ['old_tag'],
      );

      expect(xml, contains('<d:propertyupdate xmlns:d="DAV:">'));
      expect(xml, contains('<d:set>'));
      expect(xml, contains('<d:author>Jay Chou</d:author>'));
      expect(xml, contains('<d:genre>Pop &amp; Rock</d:genre>'));
      expect(xml, contains('<d:remove>'));
      expect(xml, contains('<d:old_tag/>'));
    });

    test('Generates lastmodified PROPPATCH XML with valid RFC 1123 date', () {
      final date = DateTime.utc(2024, 1, 15, 12, 0, 0);
      final xml = PropPatchXmlBuilder.buildLastModified(date);

      expect(xml, contains('<d:getlastmodified>Mon, 15 Jan 2024 12:00:00 GMT</d:getlastmodified>'));
    });
  });

  group('Streaming PropFindXmlParser Tests', () {
    test('parseStream handles fragmented byte chunks and skips parent container', () async {
      const mockXml = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/music/</d:href>
    <d:propstat>
      <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/music/Song1.flac</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
        <d:getcontentlength>123456</d:getcontentlength>
        <d:getcontenttype>audio/flac</d:getcontenttype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/music/Song2.mp3</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
        <d:getcontentlength>654321</d:getcontentlength>
        <d:getcontenttype>audio/mpeg</d:getcontenttype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>''';

      // Simulate network fragmentation by splitting into tiny chunks
      final bytes = mockXml.codeUnits;
      final chunkSize = 50;
      final chunks = <List<int>>[];
      for (int i = 0; i < bytes.length; i += chunkSize) {
        final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        chunks.add(bytes.sublist(i, end));
      }

      final stream = Stream.fromIterable(chunks);
      final files = await PropFindXmlParser.parseStream(stream, requestPath: '/music').toList();

      expect(files.length, equals(2));
      expect(files[0].name, equals('Song1.flac'));
      expect(files[0].contentLength, equals(123456));
      expect(files[0].isAudio, isTrue);

      expect(files[1].name, equals('Song2.mp3'));
      expect(files[1].contentLength, equals(654321));
    });
  });
}

