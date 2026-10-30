import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proxydom/features/settings/data/split_tunnel_prefs.dart';
import 'package:proxydom/features/vpn/data/vpn_route_policy.dart';

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

    test('accepts full web links and stores the site host', () {
      final link =
          normalizeSplitTunnelDomain('https://www.mirabreakingbad.com/');
      expect(link, isA<DomainNormalizeOk>());
      expect((link as DomainNormalizeOk).domain, 'mirabreakingbad.com');
      expect(
        (normalizeSplitTunnelDomain('http://Example.com/path?q=1#top')
                as DomainNormalizeOk)
            .domain,
        'example.com',
      );
      expect(
        (normalizeSplitTunnelDomain('example.com/path') as DomainNormalizeOk)
            .domain,
        'example.com',
      );
      expect(
        (normalizeSplitTunnelDomain('https://api.example.com/')
                as DomainNormalizeOk)
            .domain,
        'api.example.com',
      );
      expect(
        (normalizeSplitTunnelDomain('www.example.com') as DomainNormalizeOk)
            .domain,
        'example.com',
      );
    });

    test('rejects non-web schemes, IPs, wildcards, single labels, non-ascii',
        () {
      expect(
        normalizeSplitTunnelDomain('ftp://example.com'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('https://'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('https://1.2.3.4/'),
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
      expect(
        normalizeSplitTunnelDomain('https://user:pass@example.com/'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('https://[2001:db8::1]/'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('https://example.com/path with space'),
        isA<DomainNormalizeErr>(),
      );
      expect(
        normalizeSplitTunnelDomain('https://example.com:bad'),
        isA<DomainNormalizeErr>(),
      );
    });
  });

  group('add site', () {
    test('a pasted URL is saved as its bare host', () async {
      final result = await SplitTunnelPrefs.addSite(
        domain: 'https://www.mirabreakingbad.com/',
        label: 'Mira',
      );
      expect(result, isA<DomainNormalizeOk>());
      final sites = await SplitTunnelPrefs.loadSites();
      expect(sites.single.domain, 'mirabreakingbad.com');
      expect(sites.single.label, 'Mira');
      expect(
        await SplitTunnelPrefs.enabledDomainSuffixes(),
        contains('mirabreakingbad.com'),
      );
    });

    test('player hosts are saved and routed with the site', () async {
      final result = await SplitTunnelPrefs.addSite(
        domain: 'https://www.mirabreakingbad.com/',
        players: [
          'videoroll.net',
          'https://player.example.com/embed',
          'mirabreakingbad.com',
          'www.mirabreakingbad.com',
          'bad host',
          'videoroll.net',
        ],
      );
      expect(result, isA<DomainNormalizeOk>());
      final sites = await SplitTunnelPrefs.loadSites();
      expect(sites.single.players, ['player.example.com', 'videoroll.net']);

      final suffixes = await SplitTunnelPrefs.enabledDomainSuffixes();
      expect(
        suffixes,
        containsAll([
          'mirabreakingbad.com',
          'player.example.com',
          'videoroll.net',
        ]),
      );
      final ios = await SplitTunnelPrefs.enabledIosCustomResolutionHosts();
      expect(
        ios,
        containsAll(['mirabreakingbad.com', 'player.example.com']),
      );
    });
  });

  group('prefs defaults', () {
    test('popular RU categories default ON, TikTok stays in the tunnel',
        () async {
      expect(
        kOsnovnyeCategories.where((c) => c.defaultEnabled).length,
        kOsnovnyeCategories.length - 1,
      );
      expect(
        kTunnelOnlyOsnovnyeIds,
        contains('tiktok'),
      );
      expect(
        await SplitTunnelPrefs.osnovnyeEnabledCount(),
        kOsnovnyeCategories.length - 1,
      );
      final map = await SplitTunnelPrefs.loadOsnovnyeEnabled();
      expect(map['tiktok'], isFalse);
      expect(map['vk'], isTrue);
      expect(map['banks'], isTrue);
      expect(map['shops'], isTrue);
      expect(map['mailok'], isTrue);
      expect(map['telecom'], isTrue);
      expect(map['media'], isTrue);
      expect(map['transport'], isTrue);
      final suffixes = await SplitTunnelPrefs.enabledDomainSuffixes();
      expect(
        suffixes,
        containsAll([
          'vk.com',
          'yandex.ru',
          'kinopoisk.ru',
          'dzen.ru',
          'ozon.ru',
          'wildberries.ru',
          'wbstatic.net',
          'steampowered.com',
          'rutube.ru',
          'avito.ru',
          'sberbank.ru',
          'yoomoney.ru',
          'gazprombank.ru',
          'gosuslugi.ru',
          'mos.ru',
          'max.ru',
          'rustore.ru',
          'mail.ru',
          'ok.ru',
          'mts.ru',
          'ivi.ru',
          '2gis.ru',
        ]),
      );
      expect(suffixes, isNot(contains('tiktok.com')));
      expect(suffixes, isNot(contains('musical.ly')));
      expect(suffixes, isNot(contains('byteoversea.com')));
    });

    test('TikTok opt-in still works and is not re-forced off', () async {
      await SplitTunnelPrefs.setOsnovnyeEnabled('tiktok', true);
      expect((await SplitTunnelPrefs.loadOsnovnyeEnabled())['tiktok'], isTrue);
      final suffixes = await SplitTunnelPrefs.enabledDomainSuffixes();
      expect(suffixes, contains('tiktok.com'));
      expect(
        await SplitTunnelPrefs.osnovnyeEnabledCount(),
        kOsnovnyeCategories.length,
      );
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
      expect(
        await SplitTunnelPrefs.osnovnyeEnabledCount(),
        kOsnovnyeCategories.length - 1,
      );
      await SplitTunnelPrefs.setOsnovnyeEnabled('vk', true);
      final suffixes = await SplitTunnelPrefs.enabledDomainSuffixes();
      expect(suffixes, contains('vk.com'));
      expect(suffixes, isNot(contains('tiktok.com')));
      expect(await SplitTunnelPrefs.osnovnyeEnabledCount(),
          kOsnovnyeCategories.length - 1);
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
      expect(
        await SplitTunnelPrefs.osnovnyeEnabledCount(),
        kOsnovnyeCategories.length - 1,
      );

      await SplitTunnelPrefs.setOsnovnyeEnabled('vk', false);
      expect(
        await SplitTunnelPrefs.enabledDomainSuffixes(),
        isNot(contains('vk.com')),
      );
      expect(
        await SplitTunnelPrefs.osnovnyeEnabledCount(),
        kOsnovnyeCategories.length - 2,
      );
    });

    test('one-shot pulls a shipped TikTok default back into the tunnel',
        () async {
      SharedPreferences.setMockInitialValues({
        'split_tunnel_osnovnye_rf_defaults_v1': true,
        'split_tunnel_osnovnye_v2_defaults_v1': true,
        'split_tunnel_osnovnye_v3_defaults_v1': true,
        'split_tunnel_osnovnye_v4_defaults_v1': true,
        'split_tunnel_osnovnye_v1':
            '{"vk":true,"tiktok":true,"yandex":true,"ozon":true,"wb":true,'
                '"shops":true,"mailok":true,"telecom":true,"media":true,'
                '"transport":true}',
        'split_tunnel_disallowed_apps_v1': <String>[
          'com.zhiliaoapp.musically',
          'com.ss.android.ugc.trill',
          'ru.avito',
        ],
      });
      final map = await SplitTunnelPrefs.loadOsnovnyeEnabled();
      expect(map['tiktok'], isFalse);
      expect(
        await SplitTunnelPrefs.enabledDomainSuffixes(),
        isNot(contains('tiktok.com')),
      );
      expect(await SplitTunnelPrefs.loadDisallowedPackages(), {'ru.avito'});
      expect(await SplitTunnelPrefs.hasPendingChanges(), isTrue);

      // Runs once — a deliberate opt-in after the migration sticks.
      await SplitTunnelPrefs.setOsnovnyeEnabled('tiktok', true);
      expect((await SplitTunnelPrefs.loadOsnovnyeEnabled())['tiktok'], isTrue);
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
      await SplitTunnelPrefs.setOsnovnyeEnabled('vk', false);
      expect((await SplitTunnelPrefs.loadOsnovnyeEnabled())['vk'], isFalse);

      final first = await SplitTunnelPrefs.ensureIosSitesAllEnabledIfNeeded();
      expect(first, isTrue);
      final map = await SplitTunnelPrefs.loadOsnovnyeEnabled();
      expect(map['vk'], isTrue);
      expect(map['yandex'], isTrue);
      // iOS has no per-app split, so the all-ON seed must not push TikTok out
      // of the tunnel on iPhone either.
      expect(map['tiktok'], isFalse);
      final hosts = await SplitTunnelPrefs.enabledIosCatalogResolutionHosts();
      expect(hosts, isNot(contains('tiktok.com')));

      final second = await SplitTunnelPrefs.ensureIosSitesAllEnabledIfNeeded();
      expect(second, isFalse);
      await SplitTunnelPrefs.setOsnovnyeEnabled('vk', false);
      final third = await SplitTunnelPrefs.ensureIosSitesAllEnabledIfNeeded();
      expect(third, isFalse);
      expect((await SplitTunnelPrefs.loadOsnovnyeEnabled())['vk'], isFalse);
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

    test('v2 seed adds VK/Ozon/WB without restoring user-off v1 taxi',
        () async {
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

    test('v4 seed adds Avito without restoring user-off v3 packages', () async {
      SharedPreferences.setMockInitialValues({
        'split_tunnel_seeded_bypass_v1': true,
        'split_tunnel_seeded_bypass_v2': true,
        'split_tunnel_seeded_bypass_v3': true,
      });
      expect(kDefaultBypassPackagesV4, contains('ru.avito'));
      expect(
        kDefaultBypassPackagesV4.any(kTunnelOnlyBypassPackages.contains),
        isFalse,
      );
      expect(
        kDefaultBypassPackages.any(kTunnelOnlyBypassPackages.contains),
        isFalse,
      );
      final added = await SplitTunnelPrefs.seedDefaultBypassIfNeeded([
        'ru.oneme.app',
        'ru.avito',
        'com.zhiliaoapp.musically',
      ]);
      expect(added, isTrue);
      expect(await SplitTunnelPrefs.loadDisallowedPackages(), {'ru.avito'});
      final again = await SplitTunnelPrefs.seedDefaultBypassIfNeeded([
        'ru.oneme.app',
        'ru.avito',
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
      final hosts = await SplitTunnelPrefs.enabledIosCatalogResolutionHosts();
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
