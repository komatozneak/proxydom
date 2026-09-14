/// Campaign / personal referral codes (`teremokconnect://ref?code=`).
String normalizeReferralCode(String raw) {
  return raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}

Uri referralDeepLink(String raw) {
  final n = normalizeReferralCode(raw);
  return Uri(
    scheme: 'teremokconnect',
    host: 'ref',
    queryParameters: {'code': n},
  );
}

String? referralCodeFromUri(Uri uri) {
  if (uri.scheme != 'teremokconnect') return null;
  if (uri.host != 'ref') return null;
  final code = uri.queryParameters['code'];
  if (code == null || code.trim().isEmpty) return null;
  return normalizeReferralCode(code);
}
