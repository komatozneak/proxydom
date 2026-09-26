import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/vpn_session_inputs.dart';
import 'package:teremok_connect/features/vpn/data/xray_config_builder.dart';

void main() {
  const testCreds = VlessRealityCreds(
    protocol: 'vless',
    uuid: 'test-uuid-1234',
    serverPort: 443,
    flow: 'xtls-rprx-vision',
    transport: 'tcp',
    security: 'reality',
    serverName: 'www.cloudflare.com',
    publicKey: 'testPublicKey123',
    shortId: 'abcd1234',
    fingerprint: 'chrome',
    spiderX: '/',
  );

  const alternateCreds = VlessRealityCreds(
    protocol: 'vless',
    uuid: 'alternate-uuid',
    serverPort: 8443,
    transport: 'raw',
    security: 'reality',
    serverName: 'alternate.example',
    publicKey: 'alternatePublicKey',
    shortId: 'ef567890',
    fingerprint: 'firefox',
    spiderX: '/probe',
  );

  const testHops = [
    EgressHop(
      id: 'node1',
      host: '1.2.3.4',
      label: 'Node 1',
      creds: testCreds,
    ),
    EgressHop(
      id: 'node2',
      host: '5.6.7.8',
      label: 'Node 2',
      creds: alternateCreds,
    ),
  ];

  const testTun = TunParams(
    mtu: 1500,
    address: '10.255.255.1',
    addressPrefix: 30,
    controlPlaneHosts: ['10.0.0.1'],
    logLevel: 'info',
  );

  VpnSessionInputs makeInputs({
    bool includeAdsBlock = false,
    bool includeOgonAdsAll = false,
    bool includeBundledRu = true,
    bool includeGovRu = false,
    bool useHevTunBridge = false,
    List<String> directDomainSuffixes = const [],
    List<String> directIpCidrs = const [],
    List<String> proxyIpCidrs = const [],
  }) {
    return VpnSessionInputs(
      hops: testHops,
      route: RoutePolicy(
        includeAdsBlock: includeAdsBlock,
        includeOgonAdsAll: includeOgonAdsAll,
        includeBundledRuRuleSets: includeBundledRu,
        includeGovRuRuleSets: includeGovRu,
        useHevTunBridge: useHevTunBridge,
        directDomainSuffixes: directDomainSuffixes,
        directIpCidrs: directIpCidrs,
        proxyIpCidrs: proxyIpCidrs,
      ),
      tun: testTun,
    );
  }

  Map<String, dynamic> buildAndParse(VpnSessionInputs inputs) {
    final json =
        XrayConfigBuilder.buildCandidateConfigs(inputs).first.configJson;
    return jsonDecode(json) as Map<String, dynamic>;
  }

  group('XrayConfigBuilder (modeless, Ogon-style)', () {
    test('produces valid JSON with required top-level keys', () {
      final config = buildAndParse(makeInputs());
      expect((config['log'] as Map)['loglevel'], 'warning');
      expect(config.containsKey('log'), isTrue);
      expect(config.containsKey('dns'), isTrue);
      expect(config.containsKey('fakedns'), isFalse);
      expect(config.containsKey('inbounds'), isTrue);
      expect(config.containsKey('outbounds'), isTrue);
      expect(config.containsKey('routing'), isTrue);
    });

    test('DNS: Google/YT via proxy; others via direct (no FakeDNS)', () {
      final config = buildAndParse(makeInputs());
      final dns = config['dns'] as Map;
      expect(dns.containsKey('hosts'), isFalse);
      expect(dns['queryStrategy'], 'UseIPv4');
      final servers = dns['servers'] as List;
      expect(servers, hasLength(4));
      expect((servers[0] as Map)['address'], '1.1.1.1');
      expect((servers[0] as Map)['outboundTag'], 'proxy');
      expect(
        ((servers[0] as Map)['domains'] as List).cast<String>(),
        contains('domain:googlevideo.com'),
      );
      expect((servers[1] as Map)['address'], '8.8.8.8');
      expect((servers[1] as Map)['outboundTag'], 'proxy');
      expect((servers[2] as Map)['address'], '77.88.8.8');
      expect((servers[2] as Map)['outboundTag'], 'direct');
      expect((servers[3] as Map)['address'], '1.1.1.1');
      expect((servers[3] as Map)['outboundTag'], 'direct');
      expect(
        servers.any((s) => (s as Map)['address'] == 'localhost'),
        isFalse,
      );
      expect(
        servers.any((s) => (s as Map)['address'] == 'fakedns'),
        isFalse,
      );
    });

    test('DNS resolver IPs route to direct before catch-all proxy', () {
      final config = buildAndParse(makeInputs());
      final rules = (config['routing'] as Map)['rules'] as List;
      final resolverRule = rules.firstWhere(
        (r) => ((r as Map)['ip'] as List?)?.contains('77.88.8.8') ?? false,
      ) as Map;
      expect(resolverRule['outboundTag'], 'direct');
      expect(
        (resolverRule['ip'] as List).cast<String>(),
        containsAll(['77.88.8.8', '77.88.8.1', '172.16.0.0/12']),
      );
      expect(
        (resolverRule['ip'] as List).cast<String>(),
        isNot(contains('1.1.1.1')),
      );
      expect(
        (resolverRule['ip'] as List).cast<String>(),
        isNot(contains('8.8.8.8')),
      );
      expect(
        (resolverRule['ip'] as List).cast<String>(),
        isNot(contains('geoip:private')),
      );
      final catchAllIdx = rules.lastIndexWhere(
        (r) =>
            (r as Map)['network'] == 'tcp' &&
            r['outboundTag'] == 'proxy',
      );
      final resolverIdx = rules.indexOf(resolverRule);
      expect(catchAllIdx, greaterThanOrEqualTo(0));
      expect(resolverIdx, lessThan(catchAllIdx));
    });

    test('port 53 DNS hijack covers tun-in + socks-in (gVisor default)', () {
      final config = buildAndParse(makeInputs());
      final rules = (config['routing'] as Map)['rules'] as List;
      final dnsRule = rules.firstWhere(
        (r) => (r as Map)['outboundTag'] == 'dns-out',
      ) as Map;
      expect(dnsRule['port'], '53');
      expect(dnsRule['outboundTag'], 'dns-out');
      expect(dnsRule['inboundTag'], ['tun-in', 'socks-in']);
    });

    test('system DNS UDP/53 resolvers bypass residual UDP block', () {
      final config = buildAndParse(makeInputs());
      final rules = (config['routing'] as Map)['rules'] as List;

      final googleDns = rules.firstWhere(
        (r) =>
            (r as Map)['network'] == 'udp' &&
            r['port'] == '53' &&
            r['outboundTag'] == 'proxy' &&
            ((r['ip'] as List?)?.contains('8.8.8.8') ?? false),
      ) as Map;
      expect(
        (googleDns['ip'] as List).cast<String>(),
        containsAll(['8.8.8.8', '8.8.4.4']),
      );

      final directDns = rules.firstWhere(
        (r) =>
            (r as Map)['network'] == 'udp' &&
            r['port'] == '53' &&
            r['outboundTag'] == 'direct' &&
            ((r['ip'] as List?)?.contains('1.1.1.1') ?? false),
      ) as Map;
      expect(
        (directDns['ip'] as List).cast<String>(),
        containsAll(['1.1.1.1', '1.0.0.1', '77.88.8.8', '77.88.8.1']),
      );

      final residualUdpIdx = rules.indexWhere(
        (r) =>
            (r as Map)['network'] == 'udp' &&
            r['outboundTag'] == 'block' &&
            r['port'] == null,
      );
      expect(residualUdpIdx, greaterThanOrEqualTo(0));
      expect(rules.indexOf(googleDns), lessThan(residualUdpIdx));
      expect(rules.indexOf(directDns), lessThan(residualUdpIdx));

      // Residual UDP block must not list resolver IPs (would re-blackhole).
      final residual = rules[residualUdpIdx] as Map;
      expect(residual.containsKey('ip'), isFalse);
      expect(residual.containsKey('port'), isFalse);
    });

    test('UDP/443 routes to quic-reject (Cronet fail-fast)', () {
      final config = buildAndParse(makeInputs());
      final outbounds = config['outbounds'] as List;
      expect(
        outbounds.any(
          (o) =>
              (o as Map)['tag'] == 'quic-reject' &&
              o['protocol'] == 'freedom' &&
              (o['settings'] as Map?)?['redirect'] == '127.0.0.1:9',
        ),
        isTrue,
      );
      final rules = (config['routing'] as Map)['rules'] as List;
      final quic = rules.firstWhere(
        (r) =>
            (r as Map)['network'] == 'udp' &&
            r['port'] == '443' &&
            r['outboundTag'] == 'quic-reject',
      ) as Map;
      expect(quic['outboundTag'], 'quic-reject');
    });

    test('category-ads-all when Ogon flag ON (FakeDNS stays OFF)', () {
      final config = buildAndParse(makeInputs(includeOgonAdsAll: true));
      expect(config.containsKey('fakedns'), isFalse);
      final servers = (config['dns'] as Map)['servers'] as List;
      expect(
        servers.any((s) => (s as Map)['address'] == 'fakedns'),
        isFalse,
      );
      final socks = (config['inbounds'] as List).firstWhere(
        (i) => (i as Map)['protocol'] == 'socks',
      ) as Map;
      expect(
        (socks['sniffing']['destOverride'] as List).cast<String>(),
        orderedEquals(['http', 'tls', 'quic']),
      );
      expect(socks['sniffing']['routeOnly'], isFalse);
      final rules = (config['routing'] as Map)['rules'] as List;
      final ads = rules.firstWhere(
        (r) =>
            ((r as Map)['domain'] as List?)?.contains(
              'geosite:category-ads-all',
            ) ??
            false,
      ) as Map;
      expect(ads['outboundTag'], 'ads-reject');
    });

    test('gVisor default: tun-in + SOCKS + no FakeDNS + IPIfNonMatch + final proxy',
        () {
      final config = buildAndParse(makeInputs());
      expect(config.containsKey('fakedns'), isFalse);
      expect((config['routing'] as Map)['domainStrategy'], 'IPIfNonMatch');
      final servers = (config['dns'] as Map)['servers'] as List;
      expect(servers, hasLength(4));
      expect((servers.first as Map)['address'], '1.1.1.1');
      expect((servers.first as Map)['outboundTag'], 'proxy');
      expect((servers.first as Map)['domains'], isNotNull);
      expect((servers[2] as Map)['address'], '77.88.8.8');
      expect((servers[2] as Map)['outboundTag'], 'direct');
      final quicOb = (config['outbounds'] as List).firstWhere(
        (o) => (o as Map)['tag'] == 'quic-reject',
      ) as Map;
      expect(quicOb['protocol'], 'freedom');
      expect((quicOb['settings'] as Map)['redirect'], '127.0.0.1:9');
      expect(
        (config['inbounds'] as List).any((i) => (i as Map)['protocol'] == 'tun'),
        isTrue,
      );
      final socks = (config['inbounds'] as List).firstWhere(
        (i) => (i as Map)['protocol'] == 'socks',
      ) as Map;
      expect((socks['settings'] as Map)['udp'], isTrue);
      expect(socks['sniffing']['routeOnly'], isFalse);
      expect(
        (socks['sniffing']['destOverride'] as List).cast<String>(),
        orderedEquals(['http', 'tls', 'quic']),
      );
      final rules = (config['routing'] as Map)['rules'] as List;
      // Nest YT contract: residual UDP blocked; final TCP → proxy.
      expect(
        rules.any(
          (r) =>
              (r as Map)['network'] == 'udp' && r['outboundTag'] == 'block',
        ),
        isTrue,
      );
      final last = rules.last as Map;
      expect(last['outboundTag'], 'proxy');
      expect(last['network'], 'tcp');
    });

    test('gVisor mode: emits tun-in when useHevTunBridge is false', () {
      final config = buildAndParse(makeInputs(useHevTunBridge: false));
      expect(config.containsKey('fakedns'), isFalse);
      final tun = (config['inbounds'] as List).firstWhere(
        (i) => (i as Map)['protocol'] == 'tun',
      ) as Map;
      expect(tun['tag'], 'tun-in');
      expect(tun['sniffing']['routeOnly'], isFalse);
      expect(
        (tun['sniffing']['destOverride'] as List).cast<String>(),
        isNot(contains('fakedns')),
      );
      expect((config['routing'] as Map)['rules'].first['inboundTag'],
          ['tun-in', 'socks-in']);
    });

    test('hev mode: SOCKS-only inbound when useHevTunBridge is true', () {
      final config = buildAndParse(makeInputs(useHevTunBridge: true));
      expect(config.containsKey('fakedns'), isFalse);
      final inbounds = config['inbounds'] as List;
      expect(inbounds.any((i) => (i as Map)['protocol'] == 'tun'), isFalse);
      final socks = inbounds.singleWhere(
        (i) => (i as Map)['protocol'] == 'socks',
      ) as Map;
      expect(socks['tag'], 'socks-in');
      expect(socks['port'], 10808);
      expect((config['routing'] as Map)['rules'].first['inboundTag'],
          ['socks-in']);
    });

    test('routing does not force teremokconnect.online direct', () {
      final config = buildAndParse(makeInputs());
      final rules = (config['routing'] as Map)['rules'] as List;
      final pinned = rules.where((r) {
        final domain = (r as Map)['domain'];
        if (domain is! List) return false;
        return domain.any(
          (entry) => entry.toString().contains('teremokconnect.online'),
        );
      });
      expect(pinned, isEmpty);
    });

    test('inbounds: tun-in + socks-in for gVisor default', () {
      final config = buildAndParse(makeInputs());
      final inbounds = config['inbounds'] as List;
      expect(inbounds, hasLength(2));
      expect(inbounds.any((i) => (i as Map)['protocol'] == 'tun'), isTrue);
      final socks = inbounds.firstWhere((i) => (i as Map)['protocol'] == 'socks') as Map;
      expect(socks['listen'], '127.0.0.1');
      expect(socks['port'], 10808);
      expect(socks['tag'], 'socks-in');
      expect((socks['settings'] as Map)['udp'], isTrue);
      expect(socks['sniffing']['enabled'], isTrue);
      expect(
        (socks['sniffing']['destOverride'] as List).cast<String>(),
        orderedEquals(['http', 'tls', 'quic']),
      );
      expect(socks['sniffing']['routeOnly'], isFalse);
      expect(
        (socks['sniffing']['destOverride'] as List).cast<String>(),
        isNot(contains('fakedns')),
      );
      expect(jsonEncode(config).contains('node-probe-in'), isFalse);
      expect(jsonEncode(config).contains('proxy-node-'), isFalse);
    });

    test('build rejects combined candidates', () {
      expect(
        () => XrayConfigBuilder.build(makeInputs()),
        throwsArgumentError,
      );
    });

    test('single hop renames VLESS to proxy, no routing balancer', () {
      final inputs = VpnSessionInputs(
        hops: [testHops.first],
        route: const RoutePolicy(includeOgonAdsAll: true),
        tun: testTun,
      );
      final config = buildAndParse(inputs);
      final outbounds = config['outbounds'] as List;
      final vless = outbounds.firstWhere(
        (o) => (o as Map)['protocol'] == 'vless',
      ) as Map;
      expect(vless['tag'], 'proxy');
      expect((config['routing'] as Map)['balancers'], isNull);
      final finalRule =
          ((config['routing'] as Map)['rules'] as List).last as Map;
      expect(finalRule['outboundTag'], 'proxy');
    });

    test('runtime configs preserve backend order and isolate candidates', () {
      final runtime = XrayConfigBuilder.buildCandidateConfigs(makeInputs());

      expect(runtime.map((item) => item.id), ['node1', 'node2']);
      expect(runtime.map((item) => item.host), ['1.2.3.4', '5.6.7.8']);
      for (var i = 0; i < runtime.length; i++) {
        final config =
            jsonDecode(runtime[i].configJson) as Map<String, dynamic>;
        final inbounds = (config['inbounds'] as List).cast<Map>();
        final vless = (config['outbounds'] as List)
            .cast<Map>()
            .where((outbound) => outbound['protocol'] == 'vless')
            .toList();
        expect(inbounds, hasLength(2));
        final socks = inbounds.firstWhere((i) => i['protocol'] == 'socks');
        expect(socks['listen'], '127.0.0.1');
        expect(socks['port'], 10808);
        expect(
          inbounds.any((i) => i['protocol'] == 'tun'),
          isTrue,
        );
        expect(vless, hasLength(1));
        expect(vless.single['tag'], 'proxy');
        expect(
          ((vless.single['settings'] as Map)['vnext'] as List)
              .single['address'],
          runtime[i].host,
        );
      }
    });

    test('ads OFF: no curated ads reject rule', () {
      final config = buildAndParse(makeInputs(includeAdsBlock: false));
      final rules = (config['routing'] as Map)['rules'] as List;
      expect(jsonEncode(rules).contains('category-ads-all'), isFalse);
      expect(
        rules.any(
          (r) =>
              (r as Map)['outboundTag'] == 'ads-reject' &&
              ((r['domain'] as List?)?.any(
                    (d) => (d as String).contains('doubleclick.net'),
                  ) ??
                  false),
        ),
        isFalse,
      );
    });

    test('ads ON curated: domains → ads-reject; never category-ads-all', () {
      final config = buildAndParse(
        makeInputs(includeAdsBlock: true, includeOgonAdsAll: false),
      );
      final rules = (config['routing'] as Map)['rules'] as List;
      expect(jsonEncode(config).contains('category-ads-all'), isFalse);
      expect(
        (config['outbounds'] as List).any(
          (o) => (o as Map)['tag'] == 'ads-reject',
        ),
        isTrue,
      );

      final reject = rules.firstWhere(
        (r) =>
            (r as Map)['outboundTag'] == 'ads-reject' &&
            ((r['domain'] as List?)?.any(
                  (d) => (d as String).contains('doubleclick.net'),
                ) ??
                false),
      ) as Map;
      final domains = (reject['domain'] as List).cast<String>();
      expect(domains, contains('domain:doubleclick.net'));
      expect(domains, contains('domain:ads.youtube.com'));
      expect(domains.any((d) => d.contains('googlevideo')), isFalse);
    });

    test('YT force-proxy before RU bundle direct', () {
      final config = buildAndParse(makeInputs());
      final rules = (config['routing'] as Map)['rules'] as List;

      // YT force-proxy rule (domain-based in single-outbound mode).
      final ytIdx = rules.indexWhere(
        (r) =>
            ((r as Map)['domain'] as List?)?.any(
              (d) => (d as String).contains('youtube.com'),
            ) ??
            false,
      );
      expect(ytIdx, greaterThanOrEqualTo(0));
      expect((rules[ytIdx] as Map)['outboundTag'], 'proxy');

      // RU bundle direct rule.
      final ruIdx = rules.indexWhere(
        (r) =>
            ((r as Map)['domain'] as List?)?.contains(
              'geosite:category-ru',
            ) ??
            false,
      );
      expect(ruIdx, greaterThanOrEqualTo(0));
      expect((rules[ruIdx] as Map)['outboundTag'], 'direct');

      // YT must come BEFORE RU.
      expect(ytIdx, lessThan(ruIdx));
    });

    test('RU bundle ON: geosite-ru + geoip:ru direct, YT force-proxy first', () {
      final config = buildAndParse(makeInputs(includeBundledRu: true));
      final rules = (config['routing'] as Map)['rules'] as List;
      expect(
        rules.any(
          (r) =>
              ((r as Map)['domain'] as List?)?.contains('geosite:category-ru') ??
              false,
        ),
        isTrue,
      );
      expect(
        rules.any(
          (r) =>
              ((r as Map)['ip'] as List?)?.contains('geoip:ru') == true &&
              r['outboundTag'] == 'direct',
        ),
        isTrue,
      );
      expect(rules.last['outboundTag'], 'proxy');
      expect(rules.last['network'], 'tcp');
    });

    test('RU bundle OFF: no geosite-ru direct', () {
      final config = buildAndParse(makeInputs(includeBundledRu: false));
      final rules = (config['routing'] as Map)['rules'] as List;
      expect(
        rules.any(
          (r) =>
              ((r as Map)['domain'] as List?)?.contains('geosite:category-ru') ??
              false,
        ),
        isFalse,
      );
      // geoip:ru stays (kGeoipRuEnabled).
      expect(
        rules.any(
          (r) =>
              ((r as Map)['ip'] as List?)?.contains('geoip:ru') == true &&
              r['outboundTag'] == 'direct',
        ),
        isTrue,
      );
    });

    test('gov RU geosite when includeGovRu', () {
      final on = buildAndParse(makeInputs(includeGovRu: true));
      final off = buildAndParse(makeInputs(includeGovRu: false));
      final onRules = (on['routing'] as Map)['rules'] as List;
      final offRules = (off['routing'] as Map)['rules'] as List;
      expect(
        onRules.any(
          (r) =>
              ((r as Map)['domain'] as List?)
                  ?.contains('geosite:category-gov-ru') ??
              false,
        ),
        isTrue,
      );
      expect(
        offRules.any(
          (r) =>
              ((r as Map)['domain'] as List?)
                  ?.contains('geosite:category-gov-ru') ??
              false,
        ),
        isFalse,
      );
    });

    test('user no-VPN domains/CIDRs → direct after RU rules', () {
      final config = buildAndParse(
        makeInputs(
          directDomainSuffixes: ['tiktok.com', 'telegram.org'],
          directIpCidrs: ['149.154.160.0/20'],
        ),
      );
      final rules = (config['routing'] as Map)['rules'] as List;
      final directDomains = rules.firstWhere(
        (r) =>
            (r as Map)['outboundTag'] == 'direct' &&
            ((r['domain'] as List?)?.contains('domain:tiktok.com') ?? false),
      ) as Map;
      expect(
        (directDomains['domain'] as List).cast<String>(),
        containsAll(['domain:tiktok.com', 'domain:telegram.org']),
      );
      final directCidrs = rules.firstWhere(
        (r) =>
            (r as Map)['outboundTag'] == 'direct' &&
            ((r['ip'] as List?)?.contains('149.154.160.0/20') ?? false),
      ) as Map;
      expect(directCidrs['outboundTag'], 'direct');
    });

    test('proxyIpCidrs force-proxy before geoip:ru', () {
      final config = buildAndParse(
        makeInputs(proxyIpCidrs: ['8.8.8.0/24', '142.250.0.0/15']),
      );
      final rules = (config['routing'] as Map)['rules'] as List;
      final cidrIdx = rules.indexWhere(
        (r) =>
            ((r as Map)['ip'] as List?)?.contains('8.8.8.0/24') == true &&
            r['outboundTag'] == 'proxy',
      );
      final ruIdx = rules.indexWhere(
        (r) =>
            ((r as Map)['ip'] as List?)?.contains('geoip:ru') == true &&
            r['outboundTag'] == 'direct',
      );
      expect(cidrIdx, greaterThanOrEqualTo(0));
      expect(ruIdx, greaterThanOrEqualTo(0));
      expect(cidrIdx, lessThan(ruIdx));
    });

    test('force-proxy suffixes stripped from user no-VPN direct list', () {
      final config = buildAndParse(
        makeInputs(
          directDomainSuffixes: ['youtube.com', 'tiktok.com', 'google.com'],
        ),
      );
      final rules = (config['routing'] as Map)['rules'] as List;
      final directRules = rules.where((r) {
        final m = r as Map;
        return m['outboundTag'] == 'direct' &&
            ((m['domain'] as List?)?.isNotEmpty ?? false);
      });
      final domains = directRules
          .expand((r) => ((r as Map)['domain'] as List).cast<String>())
          .toSet();
      expect(domains, contains('domain:tiktok.com'));
      expect(domains, isNot(contains('domain:youtube.com')));
      expect(domains, isNot(contains('domain:google.com')));
    });

    test('YT force-proxy present and no invalid ext CIDR loader', () {
      final config = buildAndParse(makeInputs());
      final rules = (config['routing'] as Map)['rules'] as List;
      final ytForce = rules.where((r) {
        final m = r as Map;
        if (m['outboundTag'] != 'proxy') return false;
        final domains = (m['domain'] as List?)?.cast<String>() ?? const [];
        return domains.any((d) => d.contains('youtube.com')) &&
            domains.any((d) => d.contains('googlevideo.com'));
      });
      expect(ytForce, isNotEmpty);
      final raw = jsonEncode(config);
      expect(raw.contains('ext:youtube-google.cidr'), isFalse);
    });

    test('candidate configs stay single-outbound (no unified balancer)', () {
      final youtubeHop = EgressHop(
        id: 'albania-yt',
        host: '185.220.101.1',
        label: 'Albania YouTube',
        creds: testCreds,
        region: 'al',
        purpose: 'youtube',
      );
      final defaultHop = EgressHop(
        id: 'us-general',
        host: '204.11.2.216',
        label: 'US Vision',
        creds: alternateCreds,
        region: 'us',
        purpose: 'general',
      );
      final inputs = VpnSessionInputs(
        hops: [youtubeHop, defaultHop],
        route: const RoutePolicy(),
        tun: testTun,
      );

      final runtime = XrayConfigBuilder.buildCandidateConfigs(inputs);
      expect(runtime, hasLength(2));
      for (final c in runtime) {
        final config = jsonDecode(c.configJson) as Map<String, dynamic>;
        expect(config.containsKey('observatory'), isFalse);
        expect((config['routing'] as Map).containsKey('balancers'), isFalse);
        final vless = (config['outbounds'] as List)
            .where((o) => (o as Map)['protocol'] == 'vless')
            .toList();
        expect(vless, hasLength(1));
        expect((vless.single as Map)['tag'], 'proxy');
        expect(c.configJson.contains('ext:youtube-google.cidr'), isFalse);
      }
    });

    test('DNS port 53 → dns-out remains before general routing', () {
      final config = buildAndParse(makeInputs());
      final rules = (config['routing'] as Map)['rules'] as List;
      final dnsIndex = rules.indexWhere(
        (r) => (r as Map)['outboundTag'] == 'dns-out',
      );
      final catchAllIdx = rules.lastIndexWhere(
        (r) => (r as Map)['network'] == 'tcp',
      );
      expect(dnsIndex, greaterThanOrEqualTo(0));
      expect(catchAllIdx, greaterThanOrEqualTo(0));
      expect(dnsIndex, lessThan(catchAllIdx));
    });

    test('control-plane IPs → direct', () {
      final config = buildAndParse(makeInputs());
      final rules = (config['routing'] as Map)['rules'] as List;
      final directIpRules = rules.where(
        (r) => (r as Map)['outboundTag'] == 'direct' && r['ip'] != null,
      );
      expect(directIpRules, isNotEmpty);
      final ips = (directIpRules.first as Map)['ip'] as List;
      expect(ips, contains('10.0.0.1/32'));
    });

    test('VLESS outbound has Reality settings', () {
      final config = buildAndParse(makeInputs());
      final outbounds = config['outbounds'] as List;
      final vless = outbounds.firstWhere(
        (o) => (o as Map)['protocol'] == 'vless',
      ) as Map;
      final stream = vless['streamSettings'] as Map;
      expect(stream['security'], 'reality');
      final reality = stream['realitySettings'] as Map;
      expect(reality['publicKey'], 'testPublicKey123');
      expect(reality['shortId'], 'abcd1234');
      expect(reality['fingerprint'], 'chrome');
      expect(reality['serverName'], 'www.cloudflare.com');
      expect(vless['settings']['packetEncoding'], 'xudp');
      final sockopt = stream['sockopt'] as Map;
      expect(sockopt['tcpNoDelay'], isTrue);
      expect(sockopt.containsKey('tcpFastOpen'), isFalse);
    });

    test('each candidate keeps its own port, credentials, and transport', () {
      final runtime = XrayConfigBuilder.buildCandidateConfigs(makeInputs());
      final config = jsonDecode(runtime[1].configJson) as Map<String, dynamic>;
      final vless = (config['outbounds'] as List)
          .where((outbound) => (outbound as Map)['protocol'] == 'vless')
          .cast<Map>()
          .toList();
      final alternate = vless.single;
      final next =
          ((alternate['settings'] as Map)['vnext'] as List).single as Map;
      final user = (next['users'] as List).single as Map;
      final stream = alternate['streamSettings'] as Map;
      final reality = stream['realitySettings'] as Map;

      expect(next['address'], '5.6.7.8');
      expect(next['port'], 8443);
      expect(user['id'], 'alternate-uuid');
      expect(user.containsKey('flow'), isFalse);
      expect(stream['network'], 'tcp');
      expect(reality['serverName'], 'alternate.example');
      expect(reality['publicKey'], 'alternatePublicKey');
      expect(reality['spiderX'], '/probe');
    });

    test('xhttp stream-one emits xhttpSettings and omits vision flow', () {
      const xhttpCreds = VlessRealityCreds(
        protocol: 'vless',
        uuid: 'xhttp-uuid',
        serverPort: 443,
        flow: 'xtls-rprx-vision', // must be ignored for xhttp
        transport: 'xhttp',
        security: 'reality',
        serverName: 'www.cloudflare.com',
        publicKey: 'xhttpPublicKey',
        shortId: '7711c319',
        fingerprint: 'chrome',
        spiderX: '/',
        path: '/teremok/xhttp',
        mode: 'stream-one',
      );
      final runtime = XrayConfigBuilder.buildCandidateConfigs(
        const VpnSessionInputs(
          hops: [
            EgressHop(
              id: 'eu-primary',
              host: '31.59.103.144',
              label: 'EU',
              creds: xhttpCreds,
            ),
          ],
          route: RoutePolicy(),
          tun: testTun,
        ),
      );
      final config = jsonDecode(runtime.single.configJson) as Map<String, dynamic>;
      final vless = (config['outbounds'] as List)
          .where((outbound) => (outbound as Map)['protocol'] == 'vless')
          .cast<Map>()
          .single;
      final user =
          ((((vless['settings'] as Map)['vnext'] as List).single as Map)['users']
                  as List)
              .single as Map;
      final stream = vless['streamSettings'] as Map;
      final xhttp = stream['xhttpSettings'] as Map;

      expect(user.containsKey('flow'), isFalse);
      expect(vless['settings'].containsKey('packetEncoding'), isFalse);
      expect(stream['network'], 'xhttp');
      expect(xhttp['path'], '/teremok/xhttp');
      expect(xhttp['mode'], 'stream-one');
      expect(stream['security'], 'reality');
    });

    test('xhttp omitted mode defaults to stream-up', () {
      const xhttpCreds = VlessRealityCreds(
        protocol: 'vless',
        uuid: 'xhttp-uuid',
        serverPort: 443,
        transport: 'xhttp',
        security: 'reality',
        serverName: 'www.cloudflare.com',
        publicKey: 'xhttpPublicKey',
        shortId: '7711c319',
        fingerprint: 'chrome',
        spiderX: '/',
        path: '/teremok/xhttp',
      );
      final runtime = XrayConfigBuilder.buildCandidateConfigs(
        const VpnSessionInputs(
          hops: [
            EgressHop(
              id: 'eu-primary',
              host: '31.59.103.144',
              label: 'EU',
              creds: xhttpCreds,
            ),
          ],
          route: RoutePolicy(),
          tun: testTun,
        ),
      );
      final config = jsonDecode(runtime.single.configJson) as Map<String, dynamic>;
      final vless = (config['outbounds'] as List)
          .where((outbound) => (outbound as Map)['protocol'] == 'vless')
          .cast<Map>()
          .single;
      final xhttp = (vless['streamSettings'] as Map)['xhttpSettings'] as Map;
      expect(xhttp['mode'], 'stream-up');
    });

    test('routing domainStrategy is IPIfNonMatch', () {
      final config = buildAndParse(makeInputs());
      expect((config['routing'] as Map)['domainStrategy'], 'IPIfNonMatch');
    });
  });
}
