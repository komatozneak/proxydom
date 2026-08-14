import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/settings/data/qs_tile_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('teremok/vpn');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('requestAdd maps StatusBarManager callback strings', () async {
    final replies = <String>['added', 'already_added', 'not_added', 'manual'];
    for (final expected in replies) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'requestAddQsTile');
        return expected;
      });
      expect(await QsTilePrefs.requestAdd(), expected);
    }
  });

  test('requestAdd returns manual when the plugin is missing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException('requestAddQsTile');
    });
    expect(await QsTilePrefs.requestAdd(), 'manual');
  });
}
