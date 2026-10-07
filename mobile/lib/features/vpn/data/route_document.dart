import 'dart:convert';

import 'dial_set.dart';
import 'share_link_parser.dart';

/// How a remote document body should be treated. Not an account.
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

/// How a parsed paste should behave on the add screen (ADR 035).
enum ShareImportDial {
  /// At least one line can start on this platform.
  dialable,

  /// One pasted URI this platform cannot start — do not add it.
  singleUnsupported,

  /// A document with no line this platform can start. Keep it; nothing starts.
  noneDialable,
}

ShareImportDial shareImportDial(
  List<ParsedShareLink> links, {
  required bool fromDocument,
}) {
  // Per link, not per scheme: a vless line with Reality must not count as
  // dialable just because the scheme is admitted on this OS.
  if (links.any(canDialLink)) {
    return ShareImportDial.dialable;
  }
  if (links.isEmpty) return ShareImportDial.dialable;
  if (!fromDocument && links.length == 1) {
    return ShareImportDial.singleUnsupported;
  }
  return ShareImportDial.noneDialable;
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
