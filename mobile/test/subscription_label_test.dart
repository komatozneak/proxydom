import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/vpn/data/share_link_parser.dart';
import 'package:proxydom/features/vpn/data/subscription_label.dart';

void main() {
  test('subscription title and server remarks keep emoji flags', () {
    const body = '''
# Teremok VPN 🏠
hysteria2://user:pass@85.155.228.235:443/?sni=hy2-yt.teremokconnect.online#YouTube · Без рекламы
hysteria2://user:pass@204.11.2.216:443/?sni=hy2-gaming.teremokconnect.online#Игровой · Низкий пинг
hysteria2://user:pass@107.181.139.193:443/?sni=hy2-in.teremokconnect.online#Индия · Местные сервисы и цены
hysteria2://user:pass@217.60.3.9:443/?sni=hy2-eu.teremokconnect.online#Латвия · Низкий пинг
hysteria2://user:pass@45.91.248.91:443/?sni=hy2-us.teremokconnect.online#США · Сервисы, нейросети, сайты
''';
    expect(titleFromSubscriptionBody(body), 'Teremok VPN 🏠');
    expect(
      decodeProfileTitle('VGVyZW1vayBWUE4g8J+MjA=='),
      isNot(contains('USER')),
    );
    final links = parseShareSubscription(body);
    expect(links, hasLength(5));
    final youtube = labelForShareLink(links[0]);
    final gaming = labelForShareLink(links[1]);
    final india = labelForShareLink(links[2]);
    final latvia = labelForShareLink(links[3]);
    final usa = labelForShareLink(links[4]);
    expect(youtube.tile, PoolTile.media);
    expect(youtube.subtitle, 'Без рекламы');
    expect(gaming.tile, PoolTile.cloud);
    expect(gaming.subtitle, 'Низкий пинг');
    expect(india.flag, '🇮🇳');
    expect(india.subtitle, 'Местные сервисы и цены');
    expect(latvia.flag, '🇱🇻');
    expect(usa.flag, '🇺🇸');
    expect(usa.subtitle, 'Сервисы, нейросети, сайты');
  });

  test('a country tag becomes the flag and leaves the name', () {
    ParsedShareLink link(String remark) => parseShareLink(
          'hysteria2://user:pass@31.59.193.35:443/?sni=example.test'
          '#${Uri.encodeComponent(remark)}',
        );

    final de = labelForShareLink(link('DE DoDoVPN | Hysteria'));
    expect(de.title, 'DoDoVPN | Hysteria');
    expect(de.flag, '🇩🇪');
    expect(de.tile, PoolTile.flag);

    final nl = labelForShareLink(link('NL DoDoVPN | Hysteria | TikTok'));
    expect(nl.title, 'DoDoVPN | Hysteria | TikTok');
    expect(nl.flag, '🇳🇱');

    final emoji = labelForShareLink(link('🇷🇺 Москва'));
    expect(emoji.title, 'Москва');
    expect(emoji.flag, '🇷🇺');

    // `WS` is the transport on this line, not Samoa.
    final websocket = labelForShareLink(link('DE DoDoVPN | WS'));
    expect(websocket.title, 'DoDoVPN | WS');
    expect(websocket.flag, '🇩🇪');
  });

  test('a manifest line is not used as the profile name', () {
    const body = '''
#proxydom-profile: eyJ2ZXJzaW9uIjoxfQ
#subscription-userinfo: upload=0; download=1; total=10
# Мой профиль
hysteria2://user:pass@203.0.113.10:443#Node
''';
    expect(titleFromSubscriptionBody(body), 'Мой профиль');
  });

  test('a profile-title body line is decoded like its header', () {
    expect(
      titleFromSubscriptionBody('#profile-title: base64:0KLQtdGA0LXQvA==\n'),
      'Терем',
    );
  });
}
