import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proxydom/features/vpn/data/hy2_import_store.dart';

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

  test('a second pasted link is kept beside the first', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Hy2ImportStore.instance;
    await store.saveInput(
      'hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie',
    );
    await store.saveInput(
      'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443'
      '?security=reality&sni=www.example.com&pbk=PUBLIC&sid=ab#Alpha',
    );
    final links = await store.load();
    expect(links, hasLength(2));
    expect(links.last.scheme, 'vless');
    expect((await store.selected())?.scheme, 'vless');
    final catalogs = await store.catalogs();
    expect(catalogs, hasLength(2));
    expect(catalogs.last.title, 'Alpha');
  });

  test('deleting one key leaves the other profile', () async {
    SharedPreferences.setMockInitialValues({});
    final store = Hy2ImportStore.instance;
    await store.saveInput(
      'hysteria2://user:pass@203.0.113.12:443/?sni=c.example#Charlie',
    );
    await store.saveInput(
      'hysteria2://user:pass@203.0.113.13:443/?sni=d.example#Delta',
    );
    await store.removeAt(0);
    final links = await store.load();
    expect(links, hasLength(1));
    expect(links.single.endpoint, contains('203.0.113.13'));
    final catalogs = await store.catalogs();
    expect(catalogs, hasLength(1));
    await store.removeCatalog(catalogs.single.id);
    expect(await store.load(), isEmpty);
  });
}
