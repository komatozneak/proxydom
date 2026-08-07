import '../../settings/data/vpn_route_mode.dart';
import 'vpn_config.dart';
import 'vpn_config_constructor.dart';
import 'vpn_route_policy.dart';
import 'vpn_service_config.dart';
import 'vpn_session_inputs.dart';

export 'vpn_config_constructor.dart' show kProxyUrlTestTag, fakeIpV4Range;
export 'vpn_route_policy.dart';

/// Thin adapter: maps legacy call sites / tests onto [VpnConfigConstructor].
///
/// Prefer [VpnConfigConstructor.build] + [VpnSessionInputs] in new code.
String buildRuntimeSingBoxJson({
  required VpnConfig config,
  required VpnServiceConfig service,
  Map<String, String> localRulePaths = const {},
  VpnRouteMode routeMode = VpnRouteMode.smart,
  bool includeBundledRuRuleSets = true,
  bool includeAdsBlock = kAdsBlockEnabled,
  bool includeGeoipRu = kGeoipRuEnabled,
  List<String> customDirectDomainSuffixes = const [],
  List<String> customProxyDomainSuffixes = const [],
  List<String> customProxyIpCidrs = const [],
}) {
  final inputs = VpnSessionInputs.fromVpnConfig(
    config: config,
    service: service,
    route: RoutePolicy(
      mode: routeMode,
      includeAdsBlock: includeAdsBlock,
      includeGeoipRu: includeGeoipRu,
      includeBundledRuRuleSets: includeBundledRuRuleSets,
      proxyDomainSuffixes: customProxyDomainSuffixes,
      proxyIpCidrs: customProxyIpCidrs,
      directDomainSuffixes: customDirectDomainSuffixes,
      localRulePaths: localRulePaths,
    ),
  );
  return VpnConfigConstructor.build(inputs);
}
