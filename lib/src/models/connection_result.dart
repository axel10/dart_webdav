/// Result of a WebDAV connection test and capability probe.
class WebDavConnectionResult {
  final bool success;
  final String message;
  final String? serverVersion;
  final String? detectedCustomPath;
  final int? statusCode;

  const WebDavConnectionResult({
    required this.success,
    required this.message,
    this.serverVersion,
    this.detectedCustomPath,
    this.statusCode,
  });

  const WebDavConnectionResult.success({
    this.message = 'WebDAV connected successfully',
    this.serverVersion,
    this.detectedCustomPath,
    this.statusCode = 207,
  }) : success = true;

  const WebDavConnectionResult.failure(
    this.message, {
    this.statusCode,
    this.detectedCustomPath,
  })  : success = false,
        serverVersion = null;

  @override
  String toString() =>
      'WebDavConnectionResult(success: $success, message: $message, path: $detectedCustomPath, status: $statusCode)';
}
