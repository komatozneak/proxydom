import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/vpn/data/hy2_import_store.dart';

void main() {
  test('saving a profile notifies listeners', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Hy2ImportStore.instance;
    final done = Completer<void>();
    final sub = store.changes.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    addTearDown(sub.cancel);

    await store.saveInput(
      'hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie',
    );
    await done.future.timeout(const Duration(seconds: 1));
    expect((await store.load()).single.endpoint, contains('203.0.113.12'));
  });
}
