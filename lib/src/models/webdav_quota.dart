/// WebDAV storage quota information (RFC 4331: Quota and Size Properties for WebDAV).
class WebDavQuota {
  /// Bytes used by the user or collection (`quota-used-bytes`).
  final int? usedBytes;

  /// Bytes available for storage (`quota-available-bytes`).
  final int? availableBytes;

  const WebDavQuota({
    this.usedBytes,
    this.availableBytes,
  });

  /// Total quota in bytes (used + available), if both are known.
  int? get totalBytes {
    if (usedBytes != null && availableBytes != null) {
      return usedBytes! + availableBytes!;
    }
    return null;
  }

  /// Usage ratio between 0.0 and 1.0, if both values are available and total > 0.
  double? get usageRatio {
    final total = totalBytes;
    if (total != null && total > 0 && usedBytes != null) {
      return (usedBytes! / total).clamp(0.0, 1.0);
    }
    return null;
  }

  @override
  String toString() =>
      'WebDavQuota(used: $usedBytes, available: $availableBytes, total: $totalBytes)';
}
