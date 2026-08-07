import '../../../core/config.dart';
import '../../settings/data/vpn_route_mode.dart';
import 'vpn_config.dart';
import 'vpn_route_policy.dart';
import 'vpn_service_config.dart';

/// VLESS + Reality credentials shared across all egress hops.
class VlessRealityCreds {
  const VlessRealityCreds({
    required this.uuid,
    required this.serverPort,
    this.flow,
    required this.tlsEnabled,
    required this.serverName,
    required this.realityEnabled,
    required this.publicKey,
    required this.shortId,
    required this.fingerprint,
  });

  final String uuid;
  final int serverPort;
  final String? flow;
  final bool tlsEnabled;
  final String serverName;
  final bool realityEnabled;
  final String publicKey;
  final String shortId;
  final String fingerprint;

  factory VlessRealityCreds.fromOutbound(SingBoxOutbound outbound) {
    final tls = outbound.tls;
    return VlessRealityCreds(
      uuid: outbound.uuid,
      serverPort: outbound.serverPort,
      flow: outbound.flow,
      tlsEnabled: tls?.enabled ?? true,
      serverName: tls?.serverName ?? '',
      realityEnabled: tls?.realityEnabled ?? true,
      publicKey: tls?.publicKey ?? '',
      shortId: tls?.shortId ?? '',
      fingerprint: tls?.fingerprint ?? 'chrome',
    );
  }
}

/// One egress hop (host rewritten; same [VlessRealityCreds]).
class EgressHop {
  const EgressHop({
    required this.id,
    required this.host,
    this.port,
    this.label,
  });

  final String id;
  final String host;
  final int? port;
  final String? label;
}

/// How traffic is routed for this session.
class RoutePolicy {
  const RoutePolicy({
    required this.mode,
    this.includeAdsBlock = kAdsBlockEnabled,
    this.includeGeoipRu = kGeoipRuEnabled,
    this.includeBundledRuRuleSets = true,
    this.proxyDomainSuffixes = const [],
    this.proxyIpCidrs = const [],
    this.directDomainSuffixes = const [],
    this.localRulePaths = const {},
  });

  final VpnRouteMode mode;

  /// Defaults to [kAdsBlockEnabled]; tests may force ON.
  final bool includeAdsBlock;

  /// Defaults to [kGeoipRuEnabled]; intentionally unused while false.
  final bool includeGeoipRu;

  /// Smart mode loads local geosite-ru / tld-ru when paths are present.
  final bool includeBundledRuRuleSets;

  final List<String> proxyDomainSuffixes;
  final List<String> proxyIpCidrs;
  final List<String> directDomainSuffixes;
  final Map<String, String> localRulePaths;
}

/// TUN inbound parameters for libbox (fd established by VpnService).
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

/// All inputs for [VpnConfigConstructor.build] — no lossy sing-box round-trip.
class VpnSessionInputs {
  const VpnSessionInputs({
    required this.creds,
    required this.hops,
    required this.route,
    required this.tun,
  });

  final VlessRealityCreds creds;
  final List<EgressHop> hops;
  final RoutePolicy route;
  final TunParams tun;

  /// Map API [VpnConfig] + prefs into typed constructor inputs.
  factory VpnSessionInputs.fromVpnConfig({
    required VpnConfig config,
    required VpnServiceConfig service,
    required RoutePolicy route,
  }) {
    final outbound = config.singBoxConfig.primaryOutbound;
    if (outbound == null) {
      throw StateError('sing-box config has no outbounds');
    }
    final candidates = config.resolveEgressCandidates();
    final hops = candidates.isEmpty
        ? [
            EgressHop(
              id: 'primary',
              host: outbound.server,
              port: outbound.serverPort,
              label: outbound.server,
            ),
          ]
        : [
            for (final c in candidates)
              EgressHop(
                id: c.id,
                host: c.host,
                port: outbound.serverPort,
                label: c.label,
              ),
          ];
    return VpnSessionInputs(
      creds: VlessRealityCreds.fromOutbound(outbound),
      hops: hops,
      route: route,
      tun: TunParams.fromService(
        service,
        logLevel: config.singBoxConfig.logLevel,
      ),
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

/// sing-box `ip_cidr` needs an address, not a DNS name.
String? ipv4Cidr(String host) {
  if (host.isEmpty || host == 'unknown') return null;
  if (_ipv4Host.hasMatch(host)) return '$host/32';
  if (host == 'api.teremokconnect.online' ||
      host.endsWith('.teremokconnect.online')) {
    return '${AppConfig.vpsIpv4}/32';
  }
  return null;
}
