/// Bot-first pair tokens (`teremokconnect://pair?token=`).
String? pairTokenFromUri(Uri uri) {
  if (uri.scheme != 'teremokconnect') return null;
  if (uri.host != 'pair') return null;
  final token = uri.queryParameters['token']?.trim();
  if (token == null || token.isEmpty) return null;
  return token;
}

Uri pairDeepLink(String token) {
  return Uri(
    scheme: 'teremokconnect',
    host: 'pair',
    queryParameters: {'token': token.trim()},
  );
}

/// Accept raw paste: full URI or bare hex token (32 chars from token_hex(16)).
String? normalizePairTokenInput(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final asUri = Uri.tryParse(trimmed);
  if (asUri != null && asUri.hasScheme) {
    final fromUri = pairTokenFromUri(asUri);
    if (fromUri != null) return fromUri;
  }
  // Bare token: 32 hex chars (contact_link store uses secrets.token_hex(16)).
  final hex = trimmed.toLowerCase();
  if (RegExp(r'^[0-9a-f]{32}$').hasMatch(hex)) {
    return hex;
  }
  return null;
}
