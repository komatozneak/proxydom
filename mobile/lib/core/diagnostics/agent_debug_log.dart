import 'dart:convert';
import 'dart:io';

/// Debug-mode NDJSON → Cursor ingest (session 65407e).
/// #region agent log
Future<void> agentDebugLog({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?> data = const {},
  String runId = 'connectRace',
}) async {
  final payload = jsonEncode({
    'sessionId': '65407e',
    'runId': runId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  });
  // Always print — Pixel often cannot reach host ingest.
  // ignore: avoid_print
  print('[DBG65407e] $hypothesisId $location $message $payload');
  try {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 400);
    final req = await client.postUrl(
      Uri.parse(
        'http://127.0.0.1:7788/ingest/0d734c13-9580-4868-a7b2-f6e858856dda',
      ),
    );
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('X-Debug-Session-Id', '65407e');
    req.add(utf8.encode(payload));
    await req.close().timeout(const Duration(milliseconds: 400));
    client.close(force: true);
  } catch (_) {
    // logcat/flutter print already emitted
  }
}
// #endregion
