import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/settings/data/site_player_discovery.dart';

void main() {
  test('collects iframe, video and player-script hosts', () {
    const html = '''
<html>
<head>
  <script src="https://player.kodik.biz/player.js"></script>
  <script src="https://mc.yandex.ru/metrika/tag.js"></script>
  <script>var player = "https://videoroll.net/embed/1";</script>
</head>
<body>
  <iframe src="https://videoroll.net/embed/1"></iframe>
  <iframe src="//player.example.com/embed/2"></iframe>
  <iframe src="https://www.google-analytics.com/collect"></iframe>
  <iframe src="/local-player"></iframe>
  <video><source src="https://cdn.example.net/video.m3u8"></video>
</body>
</html>
''';
    final domains = SitePlayerDiscovery.playerDomainsFromHtml(
      html,
      siteDomain: 'mirabreakingbad.com',
      baseUri: Uri.parse('https://mirabreakingbad.com/episodes/1'),
    );

    expect(
      domains,
      containsAll([
        'videoroll.net',
        'player.example.com',
        'cdn.example.net',
        'player.kodik.biz',
      ]),
    );
    expect(domains, isNot(contains('mirabreakingbad.com')));
    expect(domains, isNot(contains('google-analytics.com')));
    expect(domains, orderedEquals(domains.toSet().toList()..sort()));
  });

  test('ignores empty, script and non-http embeds', () {
    const html = '''
<iframe src=""></iframe>
<iframe src="javascript:void(0)"></iframe>
<iframe src="data:text/html,hi"></iframe>
<iframe src="about:blank"></iframe>
<iframe></iframe>
''';
    expect(
      SitePlayerDiscovery.playerDomainsFromHtml(
        html,
        siteDomain: 'example.com',
        baseUri: Uri.parse('https://example.com/'),
      ),
      isEmpty,
    );
  });

  test('a relative iframe resolves against the page address', () {
    const html = '<iframe src="/player/embed/7"></iframe>';
    final domains = SitePlayerDiscovery.playerDomainsFromHtml(
      html,
      siteDomain: 'example.com',
      baseUri: Uri.parse('https://example.com/'),
    );
    expect(domains, isEmpty);
  });
}
