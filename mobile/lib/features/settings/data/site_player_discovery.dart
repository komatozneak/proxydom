import 'package:dio/dio.dart';

import 'split_tunnel_prefs.dart';

/// Finds the third-party players a site embeds, so they can leave the tunnel
/// together with the site.
///
/// A site list that contains only the page host is not enough for video: the
/// player is an iframe or a video element served from another domain. That
/// domain still goes through the VPN and the player asks for the VPN to be
/// turned off. This reads the page's embeds and returns their hosts.
class SitePlayerDiscovery {
  SitePlayerDiscovery._();

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  static const _maxHtmlChars = 2000000;

  static final _embedTag = RegExp(
    r'<(?:iframe|frame|embed|video|source)\b[^>]*>',
    caseSensitive: false,
  );
  static final _srcAttr = RegExp(
    r'''(?:src|data-src|data-lazy-src|data-url)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
    caseSensitive: false,
  );
  static final _scriptTag = RegExp(
    r'<script\b[^>]*>',
    caseSensitive: false,
  );
  static final _scriptBody = RegExp(
    r'<script\b[^>]*>([\s\S]*?)</script>',
    caseSensitive: false,
  );
  static final _urlInScript = RegExp(
    r'''(?:https?:)?//[^\s"'<>\\]+''',
    caseSensitive: false,
  );

  static const _playerHints = <String>[
    'player',
    'embed',
    'video',
    'stream',
    'm3u8',
    'videoroll',
    'kodik',
    'alloha',
    'hdvb',
    'ashdi',
    'sibnet',
    'vk.com/video',
    'ok.ru/video',
    'rutube',
    'vimeo',
    'dailymotion',
    'cdn',
  ];

  /// Third-party hosts a browser would need to reach to play this page.
  ///
  /// Returns an empty list when the page cannot be read or has no embeds; a
  /// site still works without players, it just keeps the old behaviour.
  static Future<List<String>> discover(String site) async {
    final page = pageUri(site);
    if (page == null) return const [];
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        sendTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 8),
        followRedirects: true,
        maxRedirects: 5,
        responseType: ResponseType.plain,
        headers: const {
          'User-Agent': _userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'ru-RU,ru;q=0.9,en;q=0.8',
        },
      ),
    );
    try {
      final response = await dio.getUri<String>(
        page,
        options: Options(
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
      );
      final body = response.data ?? '';
      if (body.isEmpty) return const [];
      final html =
          body.length > _maxHtmlChars ? body.substring(0, _maxHtmlChars) : body;
      return playerDomainsFromHtml(
        html,
        siteDomain: page.host,
        baseUri: response.realUri,
      );
    } catch (_) {
      return const [];
    } finally {
      dio.close(force: true);
    }
  }

  /// Builds the page address to read from what the person typed.
  static Uri? pageUri(String site) {
    final text = site.trim();
    if (text.isEmpty) return null;
    final raw = text.contains('://') ? text : 'https://$text/';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  /// Pure HTML pass, so the extractor can be tested without the network.
  static List<String> playerDomainsFromHtml(
    String html, {
    required String siteDomain,
    Uri? baseUri,
  }) {
    final siteResult = normalizeSplitTunnelDomain(siteDomain);
    final site =
        siteResult is DomainNormalizeOk ? siteResult.domain : siteDomain;
    if (site.isEmpty) return const [];
    final base = baseUri ?? Uri.tryParse('https://$site/');
    if (base == null) return const [];

    final found = <String>{};

    // Player-looking embeds first, so a strip of ad iframes cannot push the
    // actual player past the cap. Any remaining iframe is still better than
    // missing the player, so a second pass fills what is left.
    for (final tag in _embedTag.allMatches(html)) {
      final src = _srcFromTag(tag.group(0)!);
      if (src == null) continue;
      _addCandidate(
        src,
        base: base,
        site: site,
        found: found,
        strong: false,
      );
      if (found.length >= kMaxSplitTunnelPlayers) break;
    }

    if (found.length < kMaxSplitTunnelPlayers) {
      for (final tag in _embedTag.allMatches(html)) {
        final src = _srcFromTag(tag.group(0)!);
        if (src == null) continue;
        _addCandidate(
          src,
          base: base,
          site: site,
          found: found,
          strong: true,
        );
        if (found.length >= kMaxSplitTunnelPlayers) break;
      }
    }

    if (found.length < kMaxSplitTunnelPlayers) {
      for (final tag in _scriptTag.allMatches(html)) {
        final src = _srcFromTag(tag.group(0)!);
        if (src == null) continue;
        _addCandidate(
          src,
          base: base,
          site: site,
          found: found,
          strong: false,
        );
        if (found.length >= kMaxSplitTunnelPlayers) break;
      }
    }

    if (found.length < kMaxSplitTunnelPlayers) {
      for (final script in _scriptBody.allMatches(html)) {
        final body = script.group(1) ?? '';
        if (!_hasPlayerHint(body)) continue;
        for (final url in _urlInScript.allMatches(body)) {
          _addCandidate(
            url.group(0)!,
            base: base,
            site: site,
            found: found,
            strong: false,
          );
          if (found.length >= kMaxSplitTunnelPlayers) break;
        }
        if (found.length >= kMaxSplitTunnelPlayers) break;
      }
    }

    return found.toList()..sort();
  }

  static String? _srcFromTag(String tag) {
    final attr = _srcAttr.firstMatch(tag);
    if (attr == null) return null;
    final value = (attr.group(1) ?? attr.group(2) ?? '').trim();
    return value.isEmpty ? null : value;
  }

  static bool _hasPlayerHint(String text) {
    final lower = text.toLowerCase();
    return _playerHints.any(lower.contains);
  }

  static void _addCandidate(
    String raw, {
    required Uri base,
    required String site,
    required Set<String> found,
    required bool strong,
  }) {
    var value = raw.trim();
    if (value.isEmpty ||
        value.startsWith('about:') ||
        value.startsWith('javascript:') ||
        value.startsWith('data:')) {
      return;
    }
    value = value.replaceAll('&amp;', '&').replaceAll('&#38;', '&');
    final parsed = Uri.tryParse(value);
    if (parsed == null) return;
    final absolute = base.resolveUri(parsed);
    if (absolute.scheme != 'http' && absolute.scheme != 'https') return;
    if (!strong && !_looksLikePlayer(absolute)) return;
    final host = absolute.host.toLowerCase();
    if (host.isEmpty || _isTracker(host)) return;
    final normalized = normalizeSplitTunnelDomain(host);
    if (normalized is! DomainNormalizeOk) return;
    final domain = normalized.domain;
    if (domain == site || domain.endsWith('.$site')) return;
    found.add(domain);
  }

  static bool _looksLikePlayer(Uri uri) {
    final hay = '${uri.host}${uri.path}'.toLowerCase();
    return _playerHints.any(hay.contains);
  }

  static bool _isTracker(String host) {
    const trackers = <String>[
      'google-analytics.com',
      'googletagmanager.com',
      'doubleclick.net',
      'googlesyndication.com',
      'googleadservices.com',
      'adservice.google.com',
      'mc.yandex.ru',
      'top-fwz1.mail.ru',
      'adriver.ru',
      'criteo.com',
      'criteo.net',
      'taboola.com',
      'outbrain.com',
      'scorecardresearch.com',
      'facebook.net',
    ];
    return trackers
        .any((suffix) => host == suffix || host.endsWith('.$suffix'));
  }
}
