import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/settings/data/split_tunnel_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('domain normalize', () {
    test('accepts example.com', () {
      final r = normalizeSplitTunnelDomain(' Example.COM. ');
      expect(r, isA<DomainNormalizeOk>());
      expect((r as DomainNormalizeOk).domain, 'example.com');
    });

    test('rejects scheme/path/ip/wildcard/single-label/non-ascii', () {
      expect(
        normalizeSplitTunnelDomain('https://example.com'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('example.com/path'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('1.2.3.4'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('*.example.com'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('localhost'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('сайт.рф'),
        isA<DomainNormalizeErr>(),
      );
    });
  });

  group('prefs defaults', () {
    test('bundled RU defaults ON', () async {
      expect(await SplitTunnelPrefs.isBundledRuEnabled(), isTrue);
    });

    test('custom list empty; add/toggle/pending', () async {
      expect(await SplitTunnelPrefs.loadSites(), isEmpty);
      final added = await SplitTunnelPrefs.addSite(domain: 'news.example.org');
      expect(added, isA<DomainNormalizeOk>());
      expect(await SplitTunnelPrefs.hasPendingChanges(), isTrue);

      var sites = await SplitTunnelPrefs.loadSites();
      expect(sites.single.domain, 'news.example.org');
      await SplitTunnelPrefs.updateSite(sites.single.copyWith(enabled: false));
      sites = await SplitTunnelPrefs.loadSites();
      expect(sites.single.enabled, isFalse);
      expect(await SplitTunnelPrefs.enabledDomainSuffixes(), isEmpty);

      await SplitTunnelPrefs.markApplied();
      expect(await SplitTunnelPrefs.hasPendingChanges(), isFalse);
    });

    test('telegram custom site expands aliases and DC cidrs', () async {
      await SplitTunnelPrefs.addSite(domain: 'telegram.org', label: 'Telegram');
      final cidrs = await SplitTunnelPrefs.enabledProxyIpCidrs();
      expect(cidrs, contains('149.154.160.0/20'));
      expect(cidrs, contains('91.108.56.0/22'));
      final suffixes = await SplitTunnelPrefs.enabledDomainSuffixes();
      expect(suffixes, contains('api.telegram.org'));
      expect(
        kSplitTunnelDomainAliases['telegram.org'],
        containsAll(['api.telegram.org', 'telegra.ph']),
      );
      expect(
        kSplitTunnelProxyIpCidrs['telegram.org'],
        contains('149.154.160.0/20'),
      );
    });

    test('purgePresetSites removes legacy preset_* rows', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'split_tunnel_custom_sites_v1',
        '[{"id":"preset_telegram_org","domain":"telegram.org","enabled":true,'
            '"label":"Telegram","subtitle":""},'
            '{"id":"abc123","domain":"mine.example.com","enabled":true,'
            '"label":"Mine","subtitle":""}]',
      );
      final removed = await SplitTunnelPrefs.purgePresetSites();
      expect(removed, 1);
      final sites = await SplitTunnelPrefs.loadSites();
      expect(sites.length, 1);
      expect(sites.single.domain, 'mine.example.com');
      expect(sites.single.isPreset, isFalse);
    });

    test('duplicate rejected', () async {
      await SplitTunnelPrefs.addSite(domain: 'a.example.com');
      final dup = await SplitTunnelPrefs.addSite(domain: 'a.example.com');
      expect(dup, isA<DomainNormalizeErr>());
      expect(
        (dup as DomainNormalizeErr).kind,
        DomainNormalizeErrorKind.duplicate,
      );
    });

    test('osnovnye defaults ru+gov ON (2/7)', () async {
      expect(kOsnovnyeCategories.length, 7);
      expect(await SplitTunnelPrefs.osnovnyeEnabledCount(), 2);
      expect(await SplitTunnelPrefs.isBundledRuEnabled(), isTrue);
      expect(await SplitTunnelPrefs.isGovRuEnabled(), isTrue);
      await SplitTunnelPrefs.setOsnovnyeEnabled('vk', true);
      final suffixes = await SplitTunnelPrefs.enabledDomainSuffixes();
      expect(suffixes, contains('vk.com'));
      expect(await SplitTunnelPrefs.osnovnyeEnabledCount(), 3);
    });

    test('disallowed apps prefs round-trip', () async {
      expect(await SplitTunnelPrefs.loadDisallowedPackages(), isEmpty);
      await SplitTunnelPrefs.setDisallowedPackage('com.example.app', true);
      expect(
        await SplitTunnelPrefs.loadDisallowedPackages(),
        contains('com.example.app'),
      );
      expect(await SplitTunnelPrefs.hasPendingChanges(), isTrue);
      await SplitTunnelPrefs.setDisallowedPackage('com.example.app', false);
      expect(await SplitTunnelPrefs.loadDisallowedPackages(), isEmpty);
    });

    test('seedDefaultBypassIfNeeded adds only installed curated packages',
        () async {
      expect(kDefaultBypassPackages, contains('ru.yandex.taxi'));
      final added = await SplitTunnelPrefs.seedDefaultBypassIfNeeded([
        'ru.yandex.taxi',
        'com.example.other',
      ]);
      expect(added, isTrue);
      expect(
        await SplitTunnelPrefs.loadDisallowedPackages(),
        {'ru.yandex.taxi'},
      );
      expect(await SplitTunnelPrefs.hasPendingChanges(), isTrue);
    });

    test('seedDefaultBypassIfNeeded does not re-add after user off', () async {
      await SplitTunnelPrefs.seedDefaultBypassIfNeeded(['ru.yandex.taxi']);
      await SplitTunnelPrefs.setDisallowedPackage('ru.yandex.taxi', false);
      expect(await SplitTunnelPrefs.loadDisallowedPackages(), isEmpty);
      final again = await SplitTunnelPrefs.seedDefaultBypassIfNeeded([
        'ru.yandex.taxi',
      ]);
      expect(again, isFalse);
      expect(await SplitTunnelPrefs.loadDisallowedPackages(), isEmpty);
    });

    test(
        'seedDefaultBypassIfNeeded skips missing packages and still marks seeded',
        () async {
      final added = await SplitTunnelPrefs.seedDefaultBypassIfNeeded([
        'com.only.other',
      ]);
      expect(added, isFalse);
      expect(await SplitTunnelPrefs.loadDisallowedPackages(), isEmpty);
      final again = await SplitTunnelPrefs.seedDefaultBypassIfNeeded([
        'ru.yandex.taxi',
      ]);
      expect(again, isFalse);
      expect(await SplitTunnelPrefs.loadDisallowedPackages(), isEmpty);
    });
  });
}
