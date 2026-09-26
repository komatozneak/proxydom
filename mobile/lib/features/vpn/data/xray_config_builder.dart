import 'dart:convert';

import 'vpn_route_policy.dart';
import 'vpn_session_inputs.dart';

/// Tag used as the traffic selector.
const kXrayProxyTag = 'proxy';

/// Regions that identify YouTube-optimized catalog nodes (no-AdSense exits).
/// Used by UI / catalog filters — not by a dual-outbound Xray balancer.
/// `al` — Albania (legacy); `uz` — Uzbekistan (primary target, Issue #83).
const kXrayYoutubeRegions = <String>['al', 'uz'];

/// Local SOCKS inbound for probes / diagnostics (not the app traffic path).
const kXraySocksPort = 10808;

/// Pure Xray-core JSON constructor for libXray on Android.
///
/// Packet path: default gVisor `protocol:tun` + setTunFd (Огонь 0.84 SoT).
/// Hev → SOCKS when [RoutePolicy.useHevTunBridge] is true (DedProxy A/B).
/// SOCKS 10808 is always present (probes / hev hop).
/// FakeDNS **OFF**. `quic-reject` UDP/443.
///
/// Modeless routing (Огонь-style):
/// - YouTube/Google force-proxy — always (TSPU; not split-tunnel);
/// - «Что работает без VPN?» list (user sites + RU bundle geosite/geoip) → direct;
/// - everything else → proxy (final).
///
/// ## Routing rule order (deterministic, top → bottom)
/// 1. port 53 → dns-out (socks-in; + tun-in when gVisor)
/// 2. control-plane domains + egress/control IPs → direct
/// 3. DNS resolver IPs / RFC1918 → direct (Yandex + private; not 1.1.1.1/8.8.8.8)
/// 4. UDP/443 → quic-reject
/// 5. YT/Google force-proxy suffixes → proxy (always)
/// 6. youtube-google.cidr → proxy (IP-first)
/// 7. ads → ads-reject (curated / experimental ads-all)
/// 8. RU geosite → direct (bundle ON)
/// 9. geoip:ru → direct when flagged
/// 10. user no-VPN domains/CIDRs → direct (force-proxy suffixes stripped)
/// 11. xray.system UDP/53 → 8.8.8.8/proxy, 1.1.1.1+Yandex/direct
/// 12. residual UDP → block
/// 13. final TCP → proxy
///
/// Dual-core (ADR 006): TrustTunnel is a separate native core selected by
/// catalog `protocol=trusttunnel` — this builder only produces Xray JSON.
class XrayConfigBuilder {
  XrayConfigBuilder._();

  /// Build one isolated runtime config per backend-ordered candidate.
  ///
  /// Each config owns the canonical SOCKS inbound on 127.0.0.1:10808 and has
  /// exactly one VLESS outbound tagged `proxy`, so Android can stop Xray and
  /// try the next complete candidate sequentially.
  static List<XrayRuntimeCandidateConfig> buildCandidateConfigs(
    VpnSessionInputs inputs,
  ) {
    return [
      for (final hop in inputs.hops)
        XrayRuntimeCandidateConfig(
          id: hop.id,
          host: hop.host,
          label: hop.label ?? hop.host,
          configJson: build(
            VpnSessionInputs(
              hops: [hop],
              route: inputs.route,
              tun: inputs.tun,
            ),
          ),
        ),
    ];
  }

  /// Build complete Xray JSON config string from typed inputs.
  static String build(VpnSessionInputs inputs) {
    final hops = inputs.hops;
    if (hops.length != 1) {
      throw ArgumentError.value(
        hops.length,
        'inputs.hops.length',
        'build requires exactly one isolated Xray candidate',
      );
    }
    final route = inputs.route;
    // Experimental only — prod keeps kXrayOgonAdsAllEnabled false.
    final useOgonAdsAll = route.includeOgonAdsAll;
    const useSocksUdp = true;
    const useQuicReject = true;
    final useHev = route.useHevTunBridge;
    final tunMtu = inputs.tun.mtu;

    final vlessOutbound = _vlessOutbound(hop: hops.single, tag: kXrayProxyTag);

    final directCidrs = inputs.directCidrs().toList();
    final adsDomains = (!useOgonAdsAll && route.includeAdsBlock)
        ? route.adsBlockDomains
            .map((s) => s.trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toList()
        : const <String>[];
    final useCuratedAds = adsDomains.isNotEmpty;
    final useRuGeositeDirect = route.includeBundledRuRuleSets;

    // Hard-guard: YT/Google force-proxy suffixes must never go direct via the
    // user «Что работает без VPN?» list (presets used to be proxy-allowlist).
    final forceProxyBare = {
      for (final s in kSmartProxyForceSuffixes) s.trim().toLowerCase(),
    };
    final customDirect = _normalizeSuffixes(
      route.directDomainSuffixes.where((s) {
        final bare = s
            .trim()
            .toLowerCase()
            .replaceFirst(RegExp(r'^domain:'), '');
        return bare.isNotEmpty && !forceProxyBare.contains(bare);
      }),
    );
    final customDirectCidrs = _normalizeCidrs(route.directIpCidrs);
    final proxyIpCidrs = _normalizeCidrs(route.proxyIpCidrs);

    final outbounds = <Map<String, dynamic>>[
      {'protocol': 'freedom', 'tag': 'direct'},
      {'protocol': 'blackhole', 'tag': 'block'},
      // Fast TCP refuse — silent blackhole makes YT wait minutes on ad hosts.
      if (useOgonAdsAll || useCuratedAds)
        {
          'protocol': 'freedom',
          'tag': 'ads-reject',
          'settings': {'redirect': '127.0.0.1:9'},
        },
      // Instant QUIC failure — silent blackhole makes Cronet wait ~15s+ on
      // googlevideo (Pixel YT.qoe connecttimeout / ad spinner). Redirect
      // refuses immediately so apps fall back to TCP→proxy (XHTTP).
      if (useQuicReject)
        {
          'protocol': 'freedom',
          'tag': 'quic-reject',
          'settings': {'redirect': '127.0.0.1:9'},
        },
      {'protocol': 'dns', 'tag': 'dns-out'},
      vlessOutbound,
    ];

    Map<String, dynamic> viaProxy(Map<String, dynamic> fields) {
      return {'type': 'field', ...fields, 'outboundTag': kXrayProxyTag};
    }

    final ytGoogleForceProxy = viaProxy({
      'domain': [for (final s in kSmartProxyForceSuffixes) 'domain:$s'],
    });

    final rules = <Map<String, dynamic>>[
      {
        'type': 'field',
        'inboundTag': useHev ? ['socks-in'] : ['tun-in', 'socks-in'],
        'port': '53',
        'outboundTag': 'dns-out',
      },
      if (directCidrs.isNotEmpty)
        {'type': 'field', 'ip': directCidrs, 'outboundTag': 'direct'},

      // Resolver RFC1918 + Yandex DNS → direct. Do NOT pin 1.1.1.1/8.8.8.8
      // here — Google/YT DNS uses those via proxy (egress-view CDN).
      {
        'type': 'field',
        'ip': [
          '77.88.8.8',
          '77.88.8.1',
          '0.0.0.0/8',
          '10.0.0.0/8',
          '127.0.0.0/8',
          '169.254.0.0/16',
          '172.16.0.0/12',
          '192.168.0.0/16',
          '224.0.0.0/4',
          '255.255.255.255/32',
        ],
        'outboundTag': 'direct',
      },

      if (useQuicReject)
        {
          'type': 'field',
          'network': 'udp',
          'port': '443',
          'outboundTag': 'quic-reject',
        },
      // All sessions: YT/Google must not fall through to RU/direct final.
      ytGoogleForceProxy,
      if (proxyIpCidrs.isNotEmpty) viaProxy({'ip': proxyIpCidrs}),
      if (useOgonAdsAll)
        {
          'type': 'field',
          'domain': ['geosite:category-ads-all'],
          'outboundTag': 'ads-reject',
        },
      if (useCuratedAds)
        {
          'type': 'field',
          'domain': [for (final d in adsDomains) 'domain:$d'],
          'outboundTag': 'ads-reject',
        },
      if (useRuGeositeDirect) ...[
        {
          'type': 'field',
          'domain': ['geosite:category-ru'],
          'outboundTag': 'direct',
        },
        {
          'type': 'field',
          'domain': ['geosite:tld-ru'],
          'outboundTag': 'direct',
        },
      ],
      if (route.includeGovRuRuleSets)
        {
          'type': 'field',
          'domain': ['geosite:category-gov-ru'],
          'outboundTag': 'direct',
        },
      if (route.includeGeoipRu)
        {
          'type': 'field',
          'ip': ['geoip:ru'],
          'outboundTag': 'direct',
        },
      if (customDirect.isNotEmpty)
        {'type': 'field', 'domain': customDirect, 'outboundTag': 'direct'},
      if (customDirectCidrs.isNotEmpty)
        {'type': 'field', 'ip': customDirectCidrs, 'outboundTag': 'direct'},
    ];

    // Xray DNS module queries use inbound tag xray.system.* — they do NOT
    // match tun-in/socks-in → dns-out. Without these rules, residual UDP→block
    // blackholes resolver traffic (Pixel: udp:1.1.1.1:53 → block → hang).
    rules.add({
      'type': 'field',
      'network': 'udp',
      'port': '53',
      'ip': ['8.8.8.8', '8.8.4.4'],
      'outboundTag': kXrayProxyTag,
    });
    rules.add({
      'type': 'field',
      'network': 'udp',
      'port': '53',
      'ip': ['1.1.1.1', '1.0.0.1', '77.88.8.8', '77.88.8.1'],
      'outboundTag': 'direct',
    });

    // Nest YT contract: residual UDP blocked (Cronet hang); final TCP → proxy.
    // App DNS stays port-53 → dns-out; QUIC UDP/443 → quic-reject (above).
    rules.add({'type': 'field', 'network': 'udp', 'outboundTag': 'block'});
    rules.add(viaProxy({'network': 'tcp'}));

    // Google/YT → DNS via proxy so A records match egress (not RU edge
    // from 77.88 direct). Everything else: Yandex then CF (UDP/53 rules above).
    final googleDnsDomains = <String>[
      for (final s in kSmartProxyForceSuffixes) 'domain:$s',
    ];
    final dnsServers = <dynamic>[
      {
        'address': '1.1.1.1',
        'outboundTag': kXrayProxyTag,
        'domains': googleDnsDomains,
      },
      {
        'address': '8.8.8.8',
        'outboundTag': kXrayProxyTag,
        'domains': googleDnsDomains,
      },
      {
        'address': '77.88.8.8',
        'outboundTag': 'direct',
      },
      {
        'address': '1.1.1.1',
        'outboundTag': 'direct',
      },
    ];

    final dns = <String, dynamic>{
      'queryStrategy': 'UseIPv4',
      'servers': dnsServers,
    };

    final destOverride = <String>['http', 'tls', 'quic'];
    final sniffing = <String, dynamic>{
      'enabled': true,
      'destOverride': destOverride,
      // Pixel TUN A/B: routeOnly=true stalled HTTPS; FakeDNS thrash rejected
      // (77.txt: gvOk timed out). Keep dial-by-sniffed-name without FakeIP.
      'routeOnly': false,
    };

    final inbounds = <Map<String, dynamic>>[
      // gVisor TUN only when hev bridge is OFF (LibXray.setTunFd).
      if (!useHev)
        {
          'protocol': 'tun',
          'tag': 'tun-in',
          'settings': {
            'name': 'xray0',
            'mtu': tunMtu,
          },
          'sniffing': sniffing,
        },
      // Probe/diagnostics when gVisor; device path via hev when enabled.
      {
        'listen': '127.0.0.1',
        'port': kXraySocksPort,
        'protocol': 'socks',
        'settings': {
          'auth': 'noauth',
          'udp': useSocksUdp,
        },
        'sniffing': sniffing,
        'tag': 'socks-in',
      },
    ];

    final config = <String, dynamic>{
      'log': {'loglevel': 'warning'},
      'dns': dns,
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': rules,
      },
    };

    return const JsonEncoder.withIndent('  ').convert(config);
  }

  static Map<String, dynamic> _vlessOutbound({
    required EgressHop hop,
    required String tag,
  }) {
    final creds = hop.creds;
    // Marzban may emit type=raw; Xray-core 26.6.x expects tcp for Reality+Vision.
    final network = switch (creds.transport.trim().toLowerCase()) {
      'raw' || 'tcp' => 'tcp',
      final other => other,
    };
    final isXhttp = network == 'xhttp' || network == 'splithttp';
    return {
      'protocol': creds.protocol,
      'tag': tag,
      'settings': {
        'vnext': [
          {
            'address': hop.host,
            'port': creds.serverPort,
            'users': [
              {
                'id': creds.uuid,
                'encryption': 'none',
                // Vision flow is incompatible with XHTTP.
                if (!isXhttp &&
                    creds.flow != null &&
                    creds.flow!.isNotEmpty)
                  'flow': creds.flow,
              },
            ],
          },
        ],
        // Required for Vision UDP (non-443); 443 is intercepted by Vision itself.
        if (!isXhttp && creds.flow != null && creds.flow!.isNotEmpty)
          'packetEncoding': 'xudp',
      },
      'streamSettings': {
        'network': network,
        'security': creds.security,
        if (isXhttp)
          'xhttpSettings': {
            'path': (creds.path == null || creds.path!.isEmpty)
                ? '/'
                : creds.path,
            'mode': (creds.mode == null || creds.mode!.isEmpty)
                ? 'stream-up'
                : creds.mode,
          },
        if (creds.security == 'reality')
          'realitySettings': {
            'show': false,
            'fingerprint': creds.fingerprint,
            'serverName': creds.serverName,
            'publicKey': creds.publicKey,
            'shortId': creds.shortId,
            'spiderX': creds.spiderX,
          },
        // Огонь-adjacent TCP tuning (safe with Vision; no Mux).
        // tcpFastOpen omitted — hangs Reality handshake on some RF paths.
        'sockopt': {
          'tcpNoDelay': true,
        },
      },
    };
  }

  static List<String> _normalizeSuffixes(Iterable<String> suffixes) {
    return suffixes
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .map((s) => s.startsWith('domain:') ? s : 'domain:$s')
        .toList();
  }

  static List<String> _normalizeCidrs(List<String> cidrs) {
    return cidrs.map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
  }
}

/// Native failover item. Metadata stays outside Xray JSON for precise errors.
final class XrayRuntimeCandidateConfig {
  const XrayRuntimeCandidateConfig({
    required this.id,
    required this.host,
    required this.label,
    required this.configJson,
  });

  final String id;
  final String host;
  final String label;
  final String configJson;

  Map<String, dynamic> toMap() => {
        'id': id,
        'host': host,
        'label': label,
        'configJson': configJson,
      };
}
