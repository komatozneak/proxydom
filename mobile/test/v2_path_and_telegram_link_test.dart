import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/v2_path_interceptor.dart';
import 'package:teremok_connect/features/account/presentation/telegram_link_dialog.dart';

void main() {
  test('mapLegacyPath remaps /session onto /app/session', () {
    expect(V2PathInterceptor.mapLegacyPath('/session'), '/app/session');
    expect(
      V2PathInterceptor.mapLegacyPath('/session/logout_all'),
      '/app/session/logout_all',
    );
    expect(V2PathInterceptor.mapLegacyPath('/app/session'), isNull);
    expect(V2PathInterceptor.mapLegacyPath('/me'), '/app/me');
  });

  test('parseTelegramDeepLink extracts bot and start payload', () {
    final parsed = parseTelegramDeepLink(
      'https://t.me/vpn_teremok_bot?start=link_abc123',
    );
    expect(parsed, isNotNull);
    expect(parsed!.bot, 'vpn_teremok_bot');
    expect(parsed.start, 'link_abc123');
  });

  test('telegramStartUri uses tg://resolve so browsers cannot drop start=', () {
    final uri = telegramStartUri(
      botUsername: 'vpn_teremok_bot',
      startPayload: 'link_abc123',
    );
    expect(uri.scheme, 'tg');
    expect(uri.host, 'resolve');
    expect(uri.queryParameters['domain'], 'vpn_teremok_bot');
    expect(uri.queryParameters['start'], 'link_abc123');
  });

  test('plain bot /start URI has no start= payload', () {
    final tg = telegramStartUri(botUsername: 'vpn_teremok_bot');
    expect(tg.queryParameters['domain'], 'vpn_teremok_bot');
    expect(tg.queryParameters.containsKey('start'), isFalse);
    final https = telegramHttpsStartUri(botUsername: 'vpn_teremok_bot');
    expect(https.host, 't.me');
    expect(https.path, '/vpn_teremok_bot');
    expect(https.queryParameters.containsKey('start'), isFalse);
    final parsed = parseTelegramDeepLink(https.toString());
    expect(parsed, isNotNull);
    expect(parsed!.bot, 'vpn_teremok_bot');
    expect(parsed.start, isEmpty);
  });

  test('telegramHttpsStartUri tariffs payload matches bot /start tariffs', () {
    final https = telegramHttpsStartUri(
      botUsername: 'vpn_teremok_bot',
      startPayload: 'tariffs',
    );
    expect(https.host, 't.me');
    expect(https.path, '/vpn_teremok_bot');
    expect(https.queryParameters['start'], 'tariffs');
    final tg = telegramStartUri(
      botUsername: 'vpn_teremok_bot',
      startPayload: 'tariffs',
    );
    expect(tg.queryParameters['start'], 'tariffs');
  });
}
