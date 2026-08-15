/// Seat invite code display helpers (ADR 011). API stores 6 alphanumeric chars.
String normalizeSeatCode(String raw) {
  return raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

String formatSeatCodeDisplay(String raw) {
  final n = normalizeSeatCode(raw);
  if (n.length == 6) {
    return '${n.substring(0, 3)}-${n.substring(3)}';
  }
  return n;
}

Uri seatJoinDeepLink(String raw) {
  final n = normalizeSeatCode(raw);
  return Uri(scheme: 'teremokconnect', host: 'join', queryParameters: {'code': n});
}

String? seatCodeFromJoinUri(Uri uri) {
  if (uri.scheme != 'teremokconnect') return null;
  if (uri.host != 'join' && uri.pathSegments.isEmpty) {
    // teremokconnect://join?code=
    final code = uri.queryParameters['code'];
    return code == null ? null : normalizeSeatCode(code);
  }
  if (uri.host == 'join') {
    final code = uri.queryParameters['code'];
    if (code != null && code.trim().isNotEmpty) {
      return normalizeSeatCode(code);
    }
    if (uri.pathSegments.isNotEmpty) {
      return normalizeSeatCode(uri.pathSegments.first);
    }
  }
  return null;
}
