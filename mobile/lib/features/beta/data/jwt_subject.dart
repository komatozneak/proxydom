import 'dart:convert';

/// Decodes JWT `sub` without verifying the signature.
///
/// Used only for local SharedPreferences keys (onboarding / usage).
/// Server APIs still authenticate via the full Bearer token.
String? jwtSubject(String? accessToken) {
  if (accessToken == null || accessToken.isEmpty) return null;
  final parts = accessToken.split('.');
  if (parts.length < 2) return null;
  try {
    final normalized = base64Url.normalize(parts[1]);
    final payload =
        jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map;
    final sub = payload['sub'];
    if (sub == null) return null;
    final id = sub.toString().trim();
    return id.isEmpty ? null : id;
  } catch (_) {
    return null;
  }
}
