import 'package:dio/dio.dart';

/// Base exception for all WebDAV operations.
class WebDavException implements Exception {
  final String message;
  final int? statusCode;
  final String? path;
  final dynamic originalError;
  final StackTrace? stackTrace;

  const WebDavException(
    this.message, {
    this.statusCode,
    this.path,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('WebDavException');
    if (statusCode != null) buffer.write(' ($statusCode)');
    buffer.write(': $message');
    if (path != null && path!.isNotEmpty) buffer.write(' [Path: $path]');
    if (originalError != null) buffer.write(' (Caused by: $originalError)');
    return buffer.toString();
  }

  factory WebDavException.fromDio(DioException dioError, {String? path}) {
    final res = dioError.response;
    final statusCode = res?.statusCode;
    final msg = dioError.message ?? dioError.toString();

    switch (statusCode) {
      case 401:
        return WebDavUnauthorizedException(
          'Unauthorized: Invalid username, password, or authentication scheme.',
          statusCode: 401,
          path: path,
          originalError: dioError,
          stackTrace: dioError.stackTrace,
        );
      case 403:
        return WebDavForbiddenException(
          'Forbidden: Access denied to the requested resource.',
          statusCode: 403,
          path: path,
          originalError: dioError,
          stackTrace: dioError.stackTrace,
        );
      case 404:
        return WebDavNotFoundException(
          'Not Found: Specified path does not exist on WebDAV server.',
          statusCode: 404,
          path: path,
          originalError: dioError,
          stackTrace: dioError.stackTrace,
        );
      case 405:
        return WebDavMethodNotAllowedException(
          'Method Not Allowed: Target path does not support this WebDAV method.',
          statusCode: 405,
          path: path,
          originalError: dioError,
          stackTrace: dioError.stackTrace,
        );
      case 409:
        return WebDavConflictException(
          'Conflict: An intermediate directory in the path might not exist.',
          statusCode: 409,
          path: path,
          originalError: dioError,
          stackTrace: dioError.stackTrace,
        );
      case 423:
        return WebDavLockedException(
          'Locked: The resource is locked by another client (RFC 4918 Lock).',
          statusCode: 423,
          path: path,
          originalError: dioError,
          stackTrace: dioError.stackTrace,
        );
      case 429:
        return WebDavRateLimitException(
          'Rate Limited: Too many requests, rate limit exceeded.',
          statusCode: 429,
          path: path,
          originalError: dioError,
          stackTrace: dioError.stackTrace,
        );
      case 507:
        return WebDavInsufficientStorageException(
          'Insufficient Storage: WebDAV server has run out of storage quota (RFC 4918).',
          statusCode: 507,
          path: path,
          originalError: dioError,
          stackTrace: dioError.stackTrace,
        );
      default:
        if (dioError.type == DioExceptionType.connectionTimeout ||
            dioError.type == DioExceptionType.sendTimeout ||
            dioError.type == DioExceptionType.receiveTimeout) {
          return WebDavTimeoutException(
            'Connection timed out: $msg',
            statusCode: statusCode,
            path: path,
            originalError: dioError,
            stackTrace: dioError.stackTrace,
          );
        }
        return WebDavException(
          msg,
          statusCode: statusCode,
          path: path,
          originalError: dioError,
          stackTrace: dioError.stackTrace,
        );
    }
  }
}

class WebDavUnauthorizedException extends WebDavException {
  const WebDavUnauthorizedException(super.message, {super.statusCode, super.path, super.originalError, super.stackTrace});
}

class WebDavForbiddenException extends WebDavException {
  const WebDavForbiddenException(super.message, {super.statusCode, super.path, super.originalError, super.stackTrace});
}

class WebDavNotFoundException extends WebDavException {
  const WebDavNotFoundException(super.message, {super.statusCode, super.path, super.originalError, super.stackTrace});
}

class WebDavMethodNotAllowedException extends WebDavException {
  const WebDavMethodNotAllowedException(super.message, {super.statusCode, super.path, super.originalError, super.stackTrace});
}

class WebDavConflictException extends WebDavException {
  const WebDavConflictException(super.message, {super.statusCode, super.path, super.originalError, super.stackTrace});
}

class WebDavLockedException extends WebDavException {
  const WebDavLockedException(super.message, {super.statusCode, super.path, super.originalError, super.stackTrace});
}

class WebDavRateLimitException extends WebDavException {
  const WebDavRateLimitException(super.message, {super.statusCode, super.path, super.originalError, super.stackTrace});
}

class WebDavInsufficientStorageException extends WebDavException {
  const WebDavInsufficientStorageException(super.message, {super.statusCode, super.path, super.originalError, super.stackTrace});
}

class WebDavTimeoutException extends WebDavException {
  const WebDavTimeoutException(super.message, {super.statusCode, super.path, super.originalError, super.stackTrace});
}

class WebDavXmlParseException extends WebDavException {
  const WebDavXmlParseException(super.message, {super.statusCode, super.path, super.originalError, super.stackTrace});
}
