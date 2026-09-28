import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';

/// Intelligent retry interceptor for WebDAV network failures, 429 (Rate Limit), and 503 (Service Unavailable).
class WebDavRetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final Duration initialDelay;
  final Duration maxDelay;

  WebDavRetryInterceptor({
    required this.dio,
    this.maxRetries = 3,
    this.initialDelay = const Duration(milliseconds: 600),
    this.maxDelay = const Duration(seconds: 10),
  });

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;
    final currentAttempt = (extra['retry_attempt'] as int? ?? 0);

    if (!_shouldRetry(err, currentAttempt)) {
      return handler.next(err);
    }

    final nextAttempt = currentAttempt + 1;
    final delay = _calculateDelay(err, nextAttempt);

    await Future.delayed(delay);

    try {
      final options = Options(
        method: err.requestOptions.method,
        headers: err.requestOptions.headers,
        responseType: err.requestOptions.responseType,
        contentType: err.requestOptions.contentType,
        validateStatus: err.requestOptions.validateStatus,
        receiveTimeout: err.requestOptions.receiveTimeout,
        sendTimeout: err.requestOptions.sendTimeout,
        extra: {
          ...err.requestOptions.extra,
          'retry_attempt': nextAttempt,
        },
      );

      final response = await dio.request(
        err.requestOptions.path,
        data: err.requestOptions.data,
        queryParameters: err.requestOptions.queryParameters,
        cancelToken: err.requestOptions.cancelToken,
        options: options,
      );

      return handler.resolve(response);
    } on DioException catch (retryErr) {
      return handler.next(retryErr);
    } catch (e) {
      return handler.next(err);
    }
  }

  bool _shouldRetry(DioException err, int currentAttempt) {
    if (currentAttempt >= maxRetries) return false;
    if (err.type == DioExceptionType.cancel) return false;

    // Retry on timeouts or connection resets
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }

    final statusCode = err.response?.statusCode;
    if (statusCode == null) return true;

    // 429 Too Many Requests (Rate limit from cloud providers or AList)
    if (statusCode == 429) return true;

    // 502 Bad Gateway / 503 Service Unavailable / 504 Gateway Timeout
    if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
      return true;
    }

    return false;
  }

  Duration _calculateDelay(DioException err, int attempt) {
    // 1. Check Retry-After header from server
    final headers = err.response?.headers;
    final retryAfterStr = headers?.value('retry-after');
    if (retryAfterStr != null && retryAfterStr.isNotEmpty) {
      final seconds = int.tryParse(retryAfterStr);
      if (seconds != null && seconds > 0 && seconds <= 30) {
        return Duration(seconds: seconds);
      }
      try {
        final date = HttpDate.parse(retryAfterStr);
        final diff = date.difference(DateTime.now());
        if (diff > Duration.zero && diff < const Duration(seconds: 30)) {
          return diff;
        }
      } catch (_) {}
    }

    // 2. Exponential backoff with jitter
    final baseMs = initialDelay.inMilliseconds * pow(2, attempt - 1);
    final jitter = (Random().nextDouble() * 200).toInt();
    final delayMs = (baseMs + jitter).toInt().clamp(
          initialDelay.inMilliseconds,
          maxDelay.inMilliseconds,
        );

    return Duration(milliseconds: delayMs);
  }
}
