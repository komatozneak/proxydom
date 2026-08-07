import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/config.dart';
import '../../settings/data/vpn_route_mode.dart';
import 'vpn_route_policy.dart';
import 'vpn_rule_sets.dart';
import 'vpn_session_inputs.dart';

/// Urltest / route tag used as the traffic selector (and VpnPingMonitor group).
const kProxyUrlTestTag = 'proxy';

/// FakeIP range kept for docs/tests — not used in Android runtime (P0 egress).
const fakeIpV4Range = '198.18.0.0/15';

/// Pure sing-box JSON constructor for libbox 1.13+ on Android.
///
/// ## Rule pipeline (fixed order)
/// 1. sniff
/// 2. hijack-dns (port 53 + protocol dns)
/// 3. udp/443 → reject (force TCP; VLESS is TCP-only)
/// 4. control-plane / egress IPs → direct
/// 5. mode-specific (sites allowlist / smart force+RU / full none)
/// 6. ads reject only when [RoutePolicy.includeAdsBlock] (prod: [kAdsBlockEnabled])
///
/// Outbounds: `direct` + vless×N from [VlessRealityCreds]+[EgressHop] + urltest.
class VpnConfigConstructor {
  VpnConfigConstructor._();

  static String build(VpnSessionInputs inputs) {
    final creds = inputs.creds;
    final hops = inputs.hops;
    final route = inputs.route;
    final tun = inputs.tun;
    final mode = route.mode;

    final childTags = <String>[];
    final vlessOutbounds = <Map<String, dynamic>>[];
    for (final hop in hops) {
      final tag = _proxyChildTag(hop.id, existing: childTags);
      childTags.add(tag);
      vlessOutbounds.add(_vlessOutbound(creds: creds, hop: hop, tag: tag));
    }

    final directCidrs = inputs.directCidrs();
    final useBundledRu = mode == VpnRouteMode.smart &&
        route.includeBundledRuRuleSets &&
        kRuDomainRuleSetTags.every(route.localRulePaths.containsKey);
    // geoip-ru stays gated by policy (always false in prod).
    final useGeoipRu = useBundledRu &&
        route.includeGeoipRu &&
        route.localRulePaths.containsKey('geoip-ru');
    final useAdsBlock =
        route.includeAdsBlock && route.localRulePaths.containsKey(kAdsRuleSetTag);

    final customDirect = switch (mode) {
      VpnRouteMode.smart => _normalizeSuffixes(route.directDomainSuffixes),
      VpnRouteMode.sites || VpnRouteMode.full => const <String>[],
    };
    final customProxy = switch (mode) {
      VpnRouteMode.sites => _normalizeSuffixes(route.proxyDomainSuffixes),
      VpnRouteMode.smart || VpnRouteMode.full => const <String>[],
    };
    final proxyIpCidrs = switch (mode) {
      VpnRouteMode.sites => _normalizeCidrs(route.proxyIpCidrs),
      VpnRouteMode.smart || VpnRouteMode.full => const <String>[],
    };

    final sitesAllowlistActive =
        mode == VpnRouteMode.sites &&
        (customProxy.isNotEmpty || proxyIpCidrs.isNotEmpty);
    final finalTag = sitesAllowlistActive ? 'direct' : kProxyUrlTestTag;
    final String? dnsDetour = sitesAllowlistActive ? null : kProxyUrlTestTag;

    final routeRules = <Map<String, dynamic>>[
      {'inbound': 'tun-in', 'action': 'sniff'},
      {
        'port': <int>[53],
        'action': 'hijack-dns',
      },
      {'protocol': 'dns', 'action': 'hijack-dns'},
      // QUIC/UDP:443 → reject so clients fall back to TCP (proxied via final).
      // With DoH fixed, direct QUIC still fails Onesie on Pixel
      // (`onesie.unavailable.host` / MalformedURLException); reject forces TCP.
      {
        'network': 'udp',
        'port': 443,
        'action': 'reject',
      },
      if (directCidrs.isNotEmpty)
        {
          'ip_cidr': directCidrs.toList(),
          'outbound': 'direct',
        },
      if (customProxy.isNotEmpty)
        {
          'domain_suffix': customProxy,
          'outbound': kProxyUrlTestTag,
        },
      if (proxyIpCidrs.isNotEmpty)
        {
          'ip_cidr': proxyIpCidrs,
          'outbound': kProxyUrlTestTag,
        },
      if (useBundledRu)
        {
          'domain_suffix': kSmartProxyForceSuffixes,
          'outbound': kProxyUrlTestTag,
        },
      if (useAdsBlock)
        {
          'domain_suffix': kAdsRejectBypassSuffixes,
          'outbound': kProxyUrlTestTag,
        },
      if (useAdsBlock)
        {
          'rule_set': kAdsRuleSetTag,
          'action': 'reject',
        },
      if (useBundledRu) ...[
        {
          'rule_set': 'geosite-category-ru',
          'outbound': 'direct',
        },
        {
          'rule_set': 'geosite-tld-ru',
          'outbound': 'direct',
        },
      ],
      if (useGeoipRu)
        {
          'rule_set': 'geoip-ru',
          'outbound': 'direct',
        },
      if (customDirect.isNotEmpty)
        {
          'domain_suffix': customDirect,
          'outbound': 'direct',
        },
    ];

    final ruleSetEntries = <Map<String, dynamic>>[
      if (useBundledRu)
        for (final tag in kRuDomainRuleSetTags)
          if (route.localRulePaths.containsKey(tag))
            {
              'type': 'local',
              'tag': tag,
              'format': 'binary',
              'path': route.localRulePaths[tag],
            },
      if (useGeoipRu)
        {
          'type': 'local',
          'tag': 'geoip-ru',
          'format': 'binary',
          'path': route.localRulePaths['geoip-ru'],
        },
      if (useAdsBlock)
        {
          'type': 'local',
          'tag': kAdsRuleSetTag,
          'format': 'binary',
          'path': route.localRulePaths[kAdsRuleSetTag],
        },
    ];

    // VLESS outbounds are TCP-only. UDP DNS with detour=proxy never resolves
    // (Pixel: ping 1.1.1.1 OK, `unknown host example.com` / sites+YT die).
    // DoH (HTTPS) rides the same TCP tunnel as browsing.
    final dnsRemote = <String, dynamic>{
      'type': dnsDetour != null ? 'https' : 'udp',
      'tag': 'dns-remote',
      'server': '1.1.1.1',
      if (dnsDetour == null) 'server_port': 53,
      if (dnsDetour != null) 'detour': dnsDetour,
    };
    final dnsHosts = <String, dynamic>{
      'type': 'hosts',
      'tag': 'dns-hosts',
      'predefined': {
        'api.teremokconnect.online': AppConfig.vpsIpv4,
      },
    };

    final runtime = <String, dynamic>{
      'log': {'level': kDebugMode ? 'debug' : tun.logLevel},
      'dns': {
        'servers': [dnsHosts, dnsRemote],
        'rules': [
          {
            'domain': ['api.teremokconnect.online'],
            'server': 'dns-hosts',
          },
        ],
        'final': 'dns-remote',
        'strategy': 'ipv4_only',
        'independent_cache': true,
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'tun0',
          'mtu': tun.mtu,
          'address': ['${tun.address}/${tun.addressPrefix}'],
          'auto_route': false,
          'stack': 'system',
        },
      ],
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'},
        ...vlessOutbounds,
        {
          'type': 'urltest',
          'tag': kProxyUrlTestTag,
          'outbounds': childTags,
          'url': 'http://www.gstatic.com/generate_204',
          'interval': '1m',
          'tolerance': 150,
        },
      ],
      'route': {
        'rules': routeRules,
        if (ruleSetEntries.isNotEmpty) 'rule_set': ruleSetEntries,
        'final': finalTag,
        'auto_detect_interface': true,
      },
    };

    return jsonEncode(runtime);
  }

  static Map<String, dynamic> _vlessOutbound({
    required VlessRealityCreds creds,
    required EgressHop hop,
    required String tag,
  }) {
    return {
      'type': 'vless',
      'tag': tag,
      'server': hop.host,
      'server_port': hop.port ?? creds.serverPort,
      'uuid': creds.uuid,
      if (creds.flow != null) 'flow': creds.flow,
      'network': 'tcp',
      'tls': {
        'enabled': creds.tlsEnabled,
        'server_name': creds.serverName,
        'utls': {'enabled': true, 'fingerprint': creds.fingerprint},
        'reality': {
          'enabled': creds.realityEnabled,
          'public_key': creds.publicKey,
          'short_id': creds.shortId,
        },
      },
    };
  }
}

String _proxyChildTag(String id, {required List<String> existing}) {
  final safe = id
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  var tag = 'proxy-${safe.isEmpty ? 'node' : safe}';
  if (tag == kProxyUrlTestTag) {
    tag = 'proxy-node';
  }
  if (!existing.contains(tag)) return tag;
  var i = 2;
  while (existing.contains('$tag-$i')) {
    i++;
  }
  return '$tag-$i';
}

List<String> _normalizeSuffixes(List<String> raw) {
  return raw
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
}

List<String> _normalizeCidrs(List<String> raw) {
  return raw
      .map((e) => e.trim())
      .where((e) => e.contains('/'))
      .toSet()
      .toList()
    ..sort();
}
