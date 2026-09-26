import '../../../core/config.dart';
import 'vpn_config.dart';
import 'vpn_route_policy.dart';
import 'vpn_service_config.dart';

/// VLESS + Reality credentials for one egress hop (Xray builder input).
class VlessRealityCreds {
  const VlessRealityCreds({
    required this.protocol,
    required this.uuid,
    required this.serverPort,
    this.flow,
    required this.transport,
    required this.security,
    required this.serverName,
    required this.publicKey,
    required this.shortId,
    required this.fingerprint,
    required this.spiderX,
    this.path,
    this.mode,
  });

  final String protocol;
  final String uuid;
  final int serverPort;
  final String? flow;
  final String transport;
  final String security;
  final String serverName;
  final String publicKey;
  final String shortId;
  final String fingerprint;
  final String spiderX;
  final String? path;
  final String? mode;

  factory VlessRealityCreds.fromCandidate(XrayCandidate candidate) {
    return VlessRealityCreds(
      protocol: candidate.protocol,
      uuid: candidate.uuid,
      serverPort: candidate.port,
      flow: candidate.flow,
      transport: candidate.transport,
      security: candidate.security,
      serverName: candidate.serverName,
      publicKey: candidate.publicKey,
      shortId: candidate.shortId,
      fingerprint: candidate.fingerprint,
      spiderX: candidate.spiderX,
      path: candidate.path,
      mode: candidate.mode,
    );
  }
}

/// One egress hop with per-candidate credentials.
class EgressHop {
  const EgressHop({
    required this.id,
    required this.host,
    this.label,
    required this.creds,
    this.region,
    this.purpose,
  });

  final String id;
  final String host;
  final String? label;
  final VlessRealityCreds creds;
  final String? region;
  final String? purpose;
}

/// How traffic is routed for this session (modeless Огонь-style).
///
/// Builder does not use a mode enum — YouTube/Google always proxy; RU bundle +
/// user «Что работает без VPN?» → direct; residual UDP blocked; final TCP → proxy.
class RoutePolicy {
  const RoutePolicy({
    this.includeAdsBlock = kXrayAdsBlockEnabled,
    this.includeOgonAdsAll = kXrayOgonAdsAllEnabled,
    this.includeGeoipRu = kGeoipRuEnabled,
    this.includeBundledRuRuleSets = true,
    this.includeGovRuRuleSets = false,
    this.useHevTunBridge = kUseHevTunBridge,
    this.adsBlockDomains = kXrayAdsBlockDomains,
    this.proxyIpCidrs = const [],
    this.directDomainSuffixes = const [],
    this.directIpCidrs = const [],
  });

  /// Defaults to [kXrayAdsBlockEnabled]; tests may force ON with curated domains.
  final bool includeAdsBlock;

  /// Огонь `geosite:category-ads-all`. Prod keeps [kXrayOgonAdsAllEnabled] false.
  final bool includeOgonAdsAll;

  /// Defaults to [kGeoipRuEnabled]; nest home-speed keeps RU IPs direct.
  final bool includeGeoipRu;

  /// Bundled RU geosite category-ru / tld-ru → direct.
  final bool includeBundledRuRuleSets;

  /// geosite:category-gov-ru → direct (Огонь «Сайты госорганов РФ»).
  final bool includeGovRuRuleSets;

  /// When true, SOCKS-only Xray inbound + hev TUN bridge (no `protocol:tun`).
  final bool useHevTunBridge;

  /// Curated ads hosts. See [kXrayAdsBlockDomains].
  final List<String> adsBlockDomains;

  /// YouTube/Google CIDRs (youtube-google.cidr) → force-proxy before RU direct.
  final List<String> proxyIpCidrs;

  /// User «works without VPN» sites → direct (force-proxy suffixes stripped).
  final List<String> directDomainSuffixes;

  /// User «works without VPN» IP ranges → direct (Telegram DC style).
  final List<String> directIpCidrs;
}

/// TUN inbound parameters (fd established by VpnService; gVisor via setTunFd).
class TunParams {
  const TunParams({
    required this.mtu,
    required this.address,
    required this.addressPrefix,
    required this.controlPlaneHosts,
    this.logLevel = 'info',
  });

  final int mtu;
  final String address;
  final int addressPrefix;
  final List<String> controlPlaneHosts;
  final String logLevel;

  factory TunParams.fromService(VpnServiceConfig service, {String? logLevel}) {
    return TunParams(
      mtu: service.mtu,
      address: service.address,
      addressPrefix: service.addressPrefix,
      controlPlaneHosts: service.controlPlaneHosts,
      logLevel: logLevel ?? 'info',
    );
  }
}

/// All inputs for [XrayConfigBuilder.build] — one hop per Xray candidate.
class VpnSessionInputs {
  const VpnSessionInputs({
    required this.hops,
    required this.route,
    required this.tun,
  });

  final List<EgressHop> hops;
  final RoutePolicy route;
  final TunParams tun;

  /// Map API [VpnConfig] + prefs into typed builder inputs.
  factory VpnSessionInputs.fromVpnConfig({
    required VpnConfig config,
    required VpnServiceConfig service,
    required RoutePolicy route,
  }) {
    final profile = config.xrayProfile;
    if (profile == null) {
      throw StateError('xray_profile required for Xray session inputs');
    }
    final hops = [
      for (final candidate in profile.candidates)
        EgressHop(
          id: candidate.id,
          host: candidate.host,
          label: candidate.label,
          creds: VlessRealityCreds.fromCandidate(candidate),
          region: candidate.region,
          purpose: candidate.purpose,
        ),
    ];
    if (hops.isEmpty) {
      throw StateError('xray_profile has no candidates');
    }
    return VpnSessionInputs(
      hops: hops,
      route: route,
      tun: TunParams.fromService(service),
    );
  }

  /// Control-plane / egress IPv4 CIDRs that must stay direct.
  Set<String> directCidrs() {
    final out = <String>{};
    for (final hop in hops) {
      final c = ipv4Cidr(hop.host);
      if (c != null) out.add(c);
    }
    for (final host in tun.controlPlaneHosts) {
      final c = ipv4Cidr(host);
      if (c != null) out.add(c);
    }
    try {
      final apiHost = Uri.parse(AppConfig.baseUrl).host;
      final c = ipv4Cidr(apiHost);
      if (c != null) out.add(c);
    } catch (_) {}
    return out;
  }
}

final _ipv4Host = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

/// Xray `ip` rules need an address, not a DNS name.
String? ipv4Cidr(String host) {
  if (host.isEmpty || host == 'unknown') return null;
  if (_ipv4Host.hasMatch(host)) return '$host/32';
  return null;
}
