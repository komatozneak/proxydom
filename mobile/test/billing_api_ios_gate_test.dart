import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/billing/data/billing_api.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('createPlategaPayment throws on iOS without HTTP', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          fail('iOS must not POST /billing/platega/create');
        },
      ),
    );
    expect(
      () => BillingApi(dio: dio).createPlategaPayment(plan: '1m'),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
