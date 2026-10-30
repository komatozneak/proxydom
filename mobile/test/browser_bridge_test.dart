import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/features/settings/data/browser_bridge.dart';
import 'package:proxydom/features/settings/data/split_tunnel_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'the extension bridge answers health and refuses web origins',
    () async {
      await BrowserBridge.instance.start();
      addTearDown(BrowserBridge.instance.stop);
      final port = BrowserBridge.instance.port;
      expect(port, isNotNull);

      final client = HttpClient();
      addTearDown(client.close);

      final health =
          await (await client.get('127.0.0.1', port!, '/health')).close();
      expect(health.statusCode, HttpStatus.ok);
      await health.drain();

      final request = await client.post('127.0.0.1', port, '/exclude');
      request.headers.contentType = ContentType.json;
      request.headers.set('origin', 'https://evil.example');
      request.write('{"url":"https://example.com/"}');
      final refused = await request.close();
      expect(refused.statusCode, HttpStatus.forbidden);
      await refused.drain();
    },
    skip: !Platform.isWindows,
  );

  test(
    'the extension supplies player hosts from the rendered page',
    () async {
      await BrowserBridge.instance.start();
      addTearDown(BrowserBridge.instance.stop);
      final port = BrowserBridge.instance.port;
      expect(port, isNotNull);

      final client = HttpClient();
      addTearDown(client.close);

      final request = await client.post('127.0.0.1', port!, '/exclude');
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'url': 'https://mirabreakingbad.com/',
          'players': [
            'https://videoroll.net/embed/1',
            'https://player.example.com/embed/2',
            'https://mirabreakingbad.com/local-player',
          ],
        }),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      expect(response.statusCode, HttpStatus.ok);
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      expect(decoded['domain'], 'mirabreakingbad.com');
      expect(decoded['players'], 2);

      final sites = await SplitTunnelPrefs.loadSites();
      expect(sites.single.domain, 'mirabreakingbad.com');
      expect(
        sites.single.players,
        ['player.example.com', 'videoroll.net'],
      );
    },
    skip: !Platform.isWindows,
  );
}
