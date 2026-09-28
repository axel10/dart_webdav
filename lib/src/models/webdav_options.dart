/// Configuration options for [WebDavClient].
class WebDavClientOptions {
  /// Base connection timeout.
  final Duration connectTimeout;

  /// Response receive timeout.
  final Duration receiveTimeout;

  /// Request send timeout.
  final Duration sendTimeout;

  /// User-Agent header string.
  final String userAgent;

  /// Whether to bypass SSL certificate validation (self-signed certs).
  final bool ignoreSsl;

  /// Max auto-retry attempts for network errors and 429/503 responses.
  final int maxRetries;

  /// Initial retry delay for exponential backoff.
  final Duration initialRetryDelay;

  /// Max retry delay ceiling for backoff.
  final Duration maxRetryDelay;

  /// Additional custom headers for every request.
  final Map<String, String> extraHeaders;

  /// Whether to send `Translate: f` header for Microsoft IIS WebDAV compatibility.
  final bool enableIisTranslateHeader;

  const WebDavClientOptions({
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 15),
    this.userAgent = 'VynodyWebDAV/1.0',
    this.ignoreSsl = false,
    this.maxRetries = 3,
    this.initialRetryDelay = const Duration(milliseconds: 600),
    this.maxRetryDelay = const Duration(seconds: 10),
    this.extraHeaders = const {},
    this.enableIisTranslateHeader = true,
  });

  WebDavClientOptions copyWith({
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    String? userAgent,
    bool? ignoreSsl,
    int? maxRetries,
    Duration? initialRetryDelay,
    Duration? maxRetryDelay,
    Map<String, String>? extraHeaders,
    bool? enableIisTranslateHeader,
  }) {
    return WebDavClientOptions(
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      userAgent: userAgent ?? this.userAgent,
      ignoreSsl: ignoreSsl ?? this.ignoreSsl,
      maxRetries: maxRetries ?? this.maxRetries,
      initialRetryDelay: initialRetryDelay ?? this.initialRetryDelay,
      maxRetryDelay: maxRetryDelay ?? this.maxRetryDelay,
      extraHeaders: extraHeaders ?? this.extraHeaders,
      enableIisTranslateHeader:
          enableIisTranslateHeader ?? this.enableIisTranslateHeader,
    );
  }
}
