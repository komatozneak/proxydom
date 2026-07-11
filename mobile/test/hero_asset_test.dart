import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onboarding_globe.png exists on disk', () {
    final file = File('assets/brand/onboarding_globe.png');
    expect(file.existsSync(), isTrue, reason: 'hero asset missing');
    expect(file.lengthSync(), greaterThan(100 * 1024));
  });

  test('onboarding_globe.png loads via rootBundle', () async {
    final data = await rootBundle.load('assets/brand/onboarding_globe.png');
    expect(data.lengthInBytes, greaterThan(100 * 1024));
  });
}
