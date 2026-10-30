import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'site_player_discovery.dart';
import 'split_tunnel_prefs.dart';

/// Loopback bridge for the browser extension.
///
/// The extension cannot read the app's prefs or call native messaging without a
/// registered host. A localhost endpoint is the smallest bridge that works on
/// Windows without installing another signed binary: the extension sends the
/// active tab address, the app adds the site and its players.
///
/// Only loopback is bound, and a request carrying a normal http(s) `Origin` is
/// refused: a web page must not be able to add itself to the direct list and
/// escape the tunnel. Extension origins (`chrome-extension://`, etc.) are
/// allowed, as is a request with no Origin at all (curl / local tooling).
class BrowserBridge {
  BrowserBridge._();

  static final BrowserBridge instance = BrowserBridge._();

  /// Must match `background.js` in `desktop/browser-extension`.
  static const List<int> ports = [47821, 47822, 47823];

  static const int _maxBodyChars = 16384;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Fires after the extension added or updated a site.
  Stream<void> get changes => _changes.stream;

  HttpServer? _server;

  int? get port => _server?.port;

  Future<void> start() async {
    if (!Platform.isWindows || _server != null) return;
    for (final candidate in ports) {
      try {
        _server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          candidate,
        );
        break;
      } on SocketException {
        continue;
      }
    }
    final server = _server;
    if (server == null) {
      debugPrint('browser bridge: no free loopback port');
      return;
    }
    server.listen((request) {
      unawaited(_handle(request));
    });
  }

  /// Closes the listener. Used by the bridge test; the app itself lives with it.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final origin = request.headers.value('origin') ?? '';
    try {
      if (!_originAllowed(origin)) {
        _cors(response, origin);
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }
      _cors(response, origin);

      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.noContent;
        await response.close();
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/health') {
        await _json(response, HttpStatus.ok, {
          'ok': true,
          'app': 'proxydom',
        });
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/exclude') {
        await _exclude(request, response);
        return;
      }
      response.statusCode = HttpStatus.notFound;
      await response.close();
    } catch (error) {
      try {
        await _json(response, HttpStatus.internalServerError, {
          'ok': false,
          'error': 'internal',
        });
      } catch (_) {
        // The client vanished; there is no one left to answer.
      }
      debugPrint('browser bridge: $error');
    }
  }

  Future<void> _exclude(HttpRequest request, HttpResponse response) async {
    if (request.headers.contentType?.mimeType != 'application/json') {
      await _json(response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'content_type',
      });
      return;
    }
    final body = await utf8.decoder.bind(request).join();
    if (body.length > _maxBodyChars) {
      await _json(response, HttpStatus.requestEntityTooLarge, {
        'ok': false,
        'error': 'body',
      });
      return;
    }
    final decoded = jsonDecode(body);
    final raw = decoded is Map ? '${decoded['url'] ?? ''}' : '';
    final normalized = normalizeSplitTunnelDomain(raw);
    if (normalized is! DomainNormalizeOk) {
      await _json(response, HttpStatus.badRequest, {
        'ok': false,
        'error': 'url',
      });
      return;
    }

    // The extension sends player URLs straight from the rendered DOM. That is
    // the only view of a page whose players exist after its JavaScript (and
    // whose HTML a local fetch cannot read through an anti-bot screen).
    final sent = decoded is Map ? decoded['players'] : null;
    final players = sent is List
        ? normalizeSplitTunnelPlayers(
            normalized.domain,
            sent.map((value) => '$value'),
          )
        : await SitePlayerDiscovery.discover(normalized.domain);
    final sites = await SplitTunnelPrefs.loadSites();
    SplitTunnelSite? existing;
    for (final site in sites) {
      if (site.domain == normalized.domain) {
        existing = site;
        break;
      }
    }

    var added = false;
    var playerCount = players.length;
    if (existing == null) {
      final result = await SplitTunnelPrefs.addSite(
        domain: normalized.domain,
        players: players,
      );
      added = result is DomainNormalizeOk;
    } else {
      final merged = normalizeSplitTunnelPlayers(normalized.domain, [
        ...existing.players,
        ...players,
      ]);
      playerCount = merged.length;
      if (merged.length != existing.players.length || !existing.enabled) {
        // Opening the extension on a site means "exclude it now", including a
        // row the person had previously switched off.
        await SplitTunnelPrefs.updateSite(
          existing.copyWith(players: merged, enabled: true),
        );
      }
    }

    _changes.add(null);
    await _json(response, HttpStatus.ok, {
      'ok': added || existing != null,
      'domain': normalized.domain,
      'added': added,
      'players': playerCount,
      'reconnect_required': true,
    });
  }

  bool _originAllowed(String origin) {
    if (origin.isEmpty) return true;
    return origin.startsWith('chrome-extension://') ||
        origin.startsWith('moz-extension://') ||
        origin.startsWith('safari-web-extension://');
  }

  void _cors(HttpResponse response, String origin) {
    response.headers.set(
      'Access-Control-Allow-Origin',
      origin.isEmpty ? '*' : origin,
    );
    response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, OPTIONS',
    );
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type',
    );
    response.headers.set('Cache-Control', 'no-store');
  }

  Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}
