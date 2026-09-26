import '../../../core/diagnostics/product_log.dart';

final _urlInText = RegExp(r'https?://\S+');

/// One subscription fetch. The path and the body stay out: a URL often
/// carries the document secret, and the body is the key list.
void logDocumentFetch({
  required String url,
  int? elapsedMs,
  int? status,
  int? links,
  int? localLinks,
  required String decision,
  String? error,
  Object? detail,
}) {
  final uri = Uri.tryParse(url.trim());
  final host = (uri == null || uri.host.isEmpty) ? 'invalid' : uri.host;
  ProductLog.event(
    'doc.fetch',
    level: documentFetchLevel(
      decision: decision,
      links: links,
      status: status,
      localLinks: localLinks,
      error: error,
    ),
    fields: {
      'scheme': uri?.scheme ?? '',
      'host': host,
      if (uri != null && uri.hasPort) 'port': uri.port,
      if (status != null) 'status': status,
      if (elapsedMs != null) 'ms': elapsedMs,
      if (links != null) 'links': links,
      'decision': decision,
      if (error != null && error.isNotEmpty) 'error': error,
      if (detail != null) 'detail': fetchErrorDetail(detail),
    },
  );
}

/// Empty document and a failed keep are warnings. A non-empty replace is info.
ProductLogLevel documentFetchLevel({
  required String decision,
  int? links,
  int? status,
  int? localLinks,
  String? error,
}) {
  if (links == 0 || decision == 'drop') return ProductLogLevel.warn;
  if (error != null && error.isNotEmpty) return ProductLogLevel.warn;
  if (status == 304 && localLinks == 0) return ProductLogLevel.warn;
  return ProductLogLevel.info;
}

/// Exception text without the document URL.
String fetchErrorDetail(Object error) {
  final raw = error.toString().replaceAll(_urlInText, '(url)');
  final flat = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= 180) return flat;
  return '${flat.substring(0, 177)}...';
}
