import 'dart:convert';

/// Authentication interface for WebDAV requests.
abstract class WebDavAuth {
  const WebDavAuth();

  /// Returns authentication headers to attach to HTTP requests.
  Map<String, String> getHeaders(String method, String uri);
}

/// HTTP Basic Authentication (RFC 7617).
class WebDavBasicAuth extends WebDavAuth {
  final String username;
  final String password;

  const WebDavBasicAuth({
    required this.username,
    required this.password,
  });

  String get authorizationHeader {
    final credentials = '$username:$password';
    return 'Basic ${base64Encode(utf8.encode(credentials))}';
  }

  @override
  Map<String, String> getHeaders(String method, String uri) {
    if (username.isEmpty && password.isEmpty) return const {};
    return {'Authorization': authorizationHeader};
  }
}

/// No authentication (anonymous).
class WebDavAnonymousAuth extends WebDavAuth {
  const WebDavAnonymousAuth();

  @override
  Map<String, String> getHeaders(String method, String uri) => const {};
}
