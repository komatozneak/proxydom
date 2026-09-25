import 'dart:convert';

import 'share_link_parser.dart';

/// How a remote document body should be treated. Not a Teremok account.
enum DocumentBodyKind { links, empty, broken }

/// What a refresh does with the saved document.
enum DocumentSyncDecision { replace, unchanged, drop, keep }

/// Classifies a 200 body. Blank or no share lines drop the document.
/// Lines that look like a supported URI but do not parse are left in place.
DocumentBodyKind classifyDocumentBody(String body) {
  final text = body.trim();
  if (text.isEmpty) return DocumentBodyKind.empty;
  if (parseShareSubscription(text).isNotEmpty) return DocumentBodyKind.links;
  final decoded = text.contains('://') ? text : (_tryBase64(text) ?? text);
  for (final line in decoded.split(RegExp(r'\r?\n'))) {
    final item = line.trim();
    if (item.isEmpty || item.startsWith('#')) continue;
    if (isShareLinkLine(item)) return DocumentBodyKind.broken;
  }
  if (!text.contains('://') && _looksLikeBase64(text)) {
    return DocumentBodyKind.broken;
  }
  return DocumentBodyKind.empty;
}

/// `404`/`410` and an empty 200 drop the document. Transport errors and
/// `5xx` keep it. `304` does not rewrite lines.
DocumentSyncDecision decideDocumentSync({
  required int status,
  String body = '',
  bool transportFailed = false,
}) {
  if (transportFailed) return DocumentSyncDecision.keep;
  if (status == 304) return DocumentSyncDecision.unchanged;
  if (status == 404 || status == 410) return DocumentSyncDecision.drop;
  if (status != 200) return DocumentSyncDecision.keep;
  switch (classifyDocumentBody(body)) {
    case DocumentBodyKind.links:
      return DocumentSyncDecision.replace;
    case DocumentBodyKind.empty:
      return DocumentSyncDecision.drop;
    case DocumentBodyKind.broken:
      return DocumentSyncDecision.keep;
  }
}

/// `profile-update-interval` is a positive hour count.
int? parseUpdateIntervalHours(String? header) {
  if (header == null) return null;
  final hours = int.tryParse(header.trim());
  if (hours == null || hours <= 0) return null;
  return hours;
}

/// Raised when a refresh must drop or keep the saved document.
class DocumentSyncException implements Exception {
  const DocumentSyncException(this.decision);

  final DocumentSyncDecision decision;
}
bool canDialScheme(String scheme, {required bool ios}) {
  final name = scheme.toLowerCase();
  if (name == 'hysteria2' || name == 'hy2') return true;
  if (ios) return false;
  return name == 'vless' || name == 'vmess' || name == 'trojan' || name == 'ss';
}

String? _tryBase64(String text) {
  final compact = text.replaceAll(RegExp(r'\s+'), '');
  final normalized = compact.replaceAll('-', '+').replaceAll('_', '/');
  final pad = normalized.length % 4 == 0
      ? normalized
      : normalized.padRight(
          normalized.length + (4 - normalized.length % 4),
          '=',
        );
  try {
    return utf8.decode(base64Decode(pad));
  } on FormatException {
    return null;
  }
}

bool _looksLikeBase64(String text) {
  final compact = text.replaceAll(RegExp(r'\s+'), '');
  if (compact.length < 16) return false;
  return RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(compact);
}
