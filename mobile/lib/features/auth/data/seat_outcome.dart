/// Result of accepting a seat invite code (Settings → enter seat code).
enum SeatAcceptOutcome {
  ok,
  notFound,
  limit,
  ownCode,
  premiumRequired,
  failed,
}

/// Result of minting a seat invite (Settings → invite device).
sealed class SeatMakeOutcome {
  const SeatMakeOutcome();
}

final class SeatMakeOk extends SeatMakeOutcome {
  const SeatMakeOk(this.code);
  final String code;
}

final class SeatMakePremiumRequired extends SeatMakeOutcome {
  const SeatMakePremiumRequired();
}

final class SeatMakeFailed extends SeatMakeOutcome {
  const SeatMakeFailed();
}

/// Non-200 seat endpoint response with status + optional API detail.
class SeatApiException implements Exception {
  SeatApiException(this.statusCode, {this.detail, this.errorCode});

  final int statusCode;
  final String? detail;
  final String? errorCode;

  @override
  String toString() =>
      'SeatApiException(status=$statusCode, code=${errorCode ?? "-"}, '
      'detail=${detail ?? "-"})';
}

/// Extracts FastAPI `detail` (string or nested error map) from a JSON body.
String? parseApiDetail(dynamic data) {
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is String && detail.trim().isNotEmpty) return detail.trim();
  if (detail is Map) {
    final error = detail['error'];
    if (error is Map) {
      final code = error['code'];
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
      if (code is String && code.trim().isNotEmpty) return code.trim();
    }
    final message = detail['message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
  }
  return null;
}

/// Nested FastAPI error code from `detail.error.code`, if present.
String? parseApiErrorCode(dynamic data) {
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is Map) {
    final error = detail['error'];
    if (error is Map) {
      final code = error['code'];
      if (code is String && code.trim().isNotEmpty) return code.trim();
    }
  }
  return null;
}

bool detailLooksLikeDeviceLimit(String? detail) {
  if (detail == null) return false;
  final d = detail.toLowerCase();
  return d.contains('device_limit') ||
      (d.contains('maximum') && d.contains('device')) ||
      d.contains('device limit');
}

bool detailLooksLikePremiumRequired(String? detail, {String? errorCode}) {
  if (errorCode == 'premium_required') return true;
  if (detail == null) return false;
  final d = detail.toLowerCase();
  return d.contains('premium_required') ||
      (d.contains('premium') && d.contains('require'));
}

bool detailLooksLikeOwnSeatCode(String? detail, {String? errorCode}) {
  if (errorCode != null && errorCode == 'own_seat_code') return true;
  if (detail == null) return false;
  final d = detail.toLowerCase();
  return d.contains('own_seat_code') ||
      d.contains('own seat') ||
      d.contains('your own seat');
}
