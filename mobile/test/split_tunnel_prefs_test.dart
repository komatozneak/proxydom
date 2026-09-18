import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teremok_connect/features/settings/data/split_tunnel_prefs.dart';
import 'package:teremok_connect/features/vpn/data/vpn_route_policy.dart';

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
    test('live RF categories default ON; TikTok stays OFF', () async {
      expect(kOsnovnyeCategories.length, 11);
      expect(
        kRfDefaultOnOsnovnyeIds,
        {
          'vk',
          'yandex',
          'ozon',
          'wb',
          'steam',
          'rutube',
          'avito',
          'banks',
          'gosuslugi',
          'max',
        },
      );
      expect(await SplitTunnelPrefs.osnovnyeEnabledCount(), 10);
      final map = await SplitTunnelPrefs.loadOsnovnyeEnabled();
      expect(map['vk'], isTrue);
      expect(map['yandex'], isTrue);
      expect(map['ozon'], isTrue);
      expect(map['wb'], isTrue);
      expect(map['steam'], isTrue);
      expect(map['rutube'], isTrue);
      expect(map['avito'], isTrue);
      expect(map['banks'], isTrue);
      expect(map['gosuslugi'], isTrue);
      expect(map['max'], isTrue);
      expect(map['tiktok'], isFalse);
      final suffixes = await SplitTunnelPrefs.enabledDomainSuffixes();
      expect(
        suffixes,
        containsAll([
          'vk.com',
          'yandex.ru',
          'kinopoisk.ru',
          'ozon.ru',
          'wildberries.ru',
          'steampowered.com',
          'rutube.ru',
          'avito.ru',
          'sberbank.ru',
          'gosuslugi.ru',
          'max.ru',
          'oneme.ru',
        ]),
      );
      expect(suffixes, isNot(contains('tiktok.com')));
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
      final suffixes = await SplitTunnelPrefs.enabledDomainSuffixes();
      expect(suffixes, isNot(contains('news.example.org')));
      expect(suffixes, contains('vk.com'));

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

    test('osnovnye vk domains feed suffixes; youtube aliases stripped for Hy2',
        () async {
      expect(kOsnovnyeCategories.length, 11);
      expect(await SplitTunnelPrefs.osnovnyeEnabledCount(), 10);
      await SplitTunnelPrefs.setOsnovnyeEnabled('vk', true);
      final suffixes = await SplitTunnelPrefs.enabledDomainSuffixes();
      expect(suffixes, contains('vk.com'));
      expect(suffixes, isNot(contains('tiktok.com')));
      expect(await SplitTunnelPrefs.osnovnyeEnabledCount(), 10);
      await SplitTunnelPrefs.addSite(domain: 'youtube.com');
      final withYt = await SplitTunnelPrefs.enabledDomainSuffixes();
      expect(withYt, contains('youtube.com'));
      expect(stripForceProxySuffixes(withYt), isNot(contains('youtube.com')));
      expect(stripForceProxySuffixes(withYt), contains('vk.com'));
    });

    test('one-shot RF defaults turn saved-false lists ON once', () async {
      SharedPreferences.setMockInitialValues({
        'split_tunnel_osnovnye_v1':
            '{"ru":true,"gov":true,"vk":false,"tiktok":false,'
                '"yandex":false,"ozon":false,"wb":false}',
      });
      final suffixes = await SplitTunnelPrefs.enabledDomainSuffixes();
      expect(
        suffixes,
        containsAll(['vk.com', 'yandex.ru', 'ozon.ru', 'wildberries.ru']),
      );
      expect(suffixes, contains('steampowered.com'));
      expect(suffixes, isNot(contains('tiktok.com')));
      expect(await SplitTunnelPrefs.osnovnyeEnabledCount(), 10);

      await SplitTunnelPrefs.setOsnovnyeEnabled('vk', false);
      expect(
        await SplitTunnelPrefs.enabledDomainSuffixes(),
        isNot(contains('vk.com')),
      );
      expect(await SplitTunnelPrefs.osnovnyeEnabledCount(), 9);
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

    test('ensureIosSitesAllEnabledIfNeeded turns off rows on once', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues({});
      await SplitTunnelPrefs.loadOsnovnyeEnabled();
      await SplitTunnelPrefs.setOsnovnyeEnabled('tiktok', false);
      await SplitTunnelPrefs.setOsnovnyeEnabled('vk', false);
      expect((await SplitTunnelPrefs.loadOsnovnyeEnabled())['tiktok'], isFalse);
      expect((await SplitTunnelPrefs.loadOsnovnyeEnabled())['vk'], isFalse);

      final first = await SplitTunnelPrefs.ensureIosSitesAllEnabledIfNeeded();
      expect(first, isTrue);
      final map = await SplitTunnelPrefs.loadOsnovnyeEnabled();
      expect(map.values.every((v) => v), isTrue);
      expect(map['tiktok'], isTrue);

      final second = await SplitTunnelPrefs.ensureIosSitesAllEnabledIfNeeded();
      expect(second, isFalse);
      await SplitTunnelPrefs.setOsnovnyeEnabled('tiktok', false);
      final third = await SplitTunnelPrefs.ensureIosSitesAllEnabledIfNeeded();
      expect(third, isFalse);
      expect((await SplitTunnelPrefs.loadOsnovnyeEnabled())['tiktok'], isFalse);
    });

    test('seedDefaultBypassIfNeeded adds only installed curated packages',
        () async {
      expect(kDefaultBypassPackages, contains('ru.yandex.taxi'));
      expect(kDefaultBypassPackages, contains('com.vkontakte.android'));
      expect(kDefaultBypassPackagesV2, contains('ru.ozon.app.android'));
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

    test('v2 seed adds VK/Ozon/WB without restoring user-off v1 taxi', () async {
      SharedPreferences.setMockInitialValues({
        'split_tunnel_seeded_bypass_v1': true,
      });
      final added = await SplitTunnelPrefs.seedDefaultBypassIfNeeded([
        'ru.yandex.taxi',
        'com.vkontakte.android',
        'ru.ozon.app.android',
        'com.wildberries.ru',
      ]);
      expect(added, isTrue);
      expect(await SplitTunnelPrefs.loadDisallowedPackages(), {
        'com.vkontakte.android',
        'ru.ozon.app.android',
        'com.wildberries.ru',
      });
      final again = await SplitTunnelPrefs.seedDefaultBypassIfNeeded([
        'ru.yandex.taxi',
        'com.vkontakte.android',
      ]);
      expect(again, isFalse);
    });

    test('v3 seed adds MAX without restoring user-off v2 packages', () async {
      SharedPreferences.setMockInitialValues({
        'split_tunnel_seeded_bypass_v1': true,
        'split_tunnel_seeded_bypass_v2': true,
      });
      expect(kDefaultBypassPackagesV3, contains('ru.oneme.app'));
      final added = await SplitTunnelPrefs.seedDefaultBypassIfNeeded([
        'com.vkontakte.android',
        'ru.oneme.app',
      ]);
      expect(added, isTrue);
      expect(await SplitTunnelPrefs.loadDisallowedPackages(), {'ru.oneme.app'});
      final again = await SplitTunnelPrefs.seedDefaultBypassIfNeeded([
        'ru.oneme.app',
        'com.vkontakte.android',
      ]);
      expect(again, isFalse);
    });
  });

  group('iOS exact resolution hosts', () {
    test('RuTube/Avito/MAX expand iosResolutionHosts', () async {
      final hosts =
          await SplitTunnelPrefs.enabledIosCatalogResolutionHosts();
      expect(hosts, contains('static.rutube.ru'));
      expect(hosts, contains('api.avito.ru'));
      expect(hosts, contains('ws-api.max.ru'));
      expect(hosts, contains('www.rutube.ru'));
    });

    test('custom site keeps only the exact typed hostname', () async {
      await SplitTunnelPrefs.addSite(domain: 'api.example.com');
      final hosts = await SplitTunnelPrefs.enabledIosCustomResolutionHosts();
      expect(hosts, ['api.example.com']);
      expect(hosts, isNot(contains('www.api.example.com')));
    });
  });
}
