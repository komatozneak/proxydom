import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/v2_path_interceptor.dart';

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
}
