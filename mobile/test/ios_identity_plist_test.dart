import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS bundle name and camera prompt are Proxy Dom', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>CFBundleDisplayName</key>'));
    expect(
      RegExp(r'<key>CFBundleDisplayName</key>\s*<string>Proxy Dom</string>')
          .hasMatch(plist),
      isTrue,
    );
    expect(
      RegExp(r'<key>CFBundleName</key>\s*<string>proxydom</string>')
          .hasMatch(plist),
      isTrue,
    );
    expect(plist.contains('Teremok'), isFalse);
    expect(plist, contains('Прокси Дом сканирует QR-код'));
  });
}
