import 'dart:convert';

import '../../../core/config.dart';
import 'node_display.dart';
import 'vpn_config.dart';
import 'vpn_node.dart';
import 'xray_config_builder.dart';

/// User-facing brand name for VPN session / fallback labels (no Marzban id).
const kVpnBrandSessionName = 'Теремок VPN';

/// Normalize outbound type for native/UI (never `"unknown"`).
String normalizeOutboundType(String? type) {
  final t = (type ?? '').trim().toLowerCase();
  if (t.isEmpty || t == 'unknown') return 'vless';
  return t;
}

/// Protocol label for Home / notification (e.g. `VLESS`).
String friendlyProtocolLabel(String? type) =>
    normalizeOutboundType(type).toUpperCase();

/// Session protocol for logs / Home: Hy2 and TrustTunnel must not fall back to VLESS.
String sessionProtocolLabel({
  required VpnConfig? config,
  String? selectedNodeProtocol,
}) {
  final selected = (selectedNodeProtocol ?? '').trim().toLowerCase();
  if (config?.isHysteriaSession == true ||
      selected == kVpnNodeProtocolHysteria2) {
    return 'HYSTERIA2';
  }
  if (config?.isTrustTunnelSession == true ||
      selected == kVpnNodeProtocolTrusttunnel) {
    return 'TRUSTTUNNEL';
  }
  if (config?.xrayProfile?.candidates.isNotEmpty == true) {
    return friendlyProtocolLabel(config!.primaryCandidate.protocol);
  }
  return friendlyProtocolLabel('vless');
}

/// Human label for region/node; never Marzban `username`.
///
/// Order: explicit [displayLabel] → [VpnConfig.nodeHost] /
/// [VpnConfig.expectedEgressHost] → primary candidate host → brand name.
String resolveVpnDisplayLabel(VpnConfig config, {String? displayLabel}) {
  final explicit = displayLabel?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;

  final hosts = <String>{};
  void addHost(String? value) {
    final h = value?.trim();
    if (h != null && h.isNotEmpty && h != 'unknown') {
      hosts.add(h);
    }
  }

  addHost(config.nodeHost);
  addHost(config.expectedEgressHost);
  final xray = config.xrayProfile;
  if (xray != null && xray.candidates.isNotEmpty) {
    addHost(config.primaryCandidate.host);
  }

  for (final host in hosts) {
    final known = placeForKnownHost(host);
    if (known != null) return known.title;
  }

  for (final host in hosts) {
    final place = placeForHost(host);
    if (!_isGenericServerPlaceholder(place.title)) {
      return place.title;
    }
  }

  return kVpnBrandSessionName;
}

/// Home card / logs: catalog label wins even when Flutter has no live mint yet.
String connectedServerName({VpnConfig? config, String? displayLabel}) {
  final explicit = displayLabel?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  if (config != null) {
    return resolveVpnDisplayLabel(config);
  }
  return kVpnBrandSessionName;
}

bool _isGenericServerPlaceholder(String title) =>
    RegExp(r'^(Сервер|Server) \d+$').hasMatch(title);

/// Peer address for TUN (/30) used by [VpnService.Builder.addDnsServer].
String tunDnsPeerAddress(String address, int prefixLength) {
  final octets = address.split('.').map(int.parse).toList();
  if (octets.length != 4) return '172.19.0.2';

  final ip =
      (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];
  final mask = prefixLength == 0 ? 0 : (-1 << (32 - prefixLength));
  final network = ip & mask;
  final broadcast = network | (~mask & 0xffffffff);
  final host1 = network + 1;
  final host2 = broadcast - 1;

  final int peer;
  if (ip == host1) {
    peer = host2;
  } else if (ip == host2) {
    peer = host1;
  } else {
    peer = host2;
  }
  return '${(peer >> 24) & 0xff}.${(peer >> 16) & 0xff}'
      '.${(peer >> 8) & 0xff}.${peer & 0xff}';
}

/// Parameters for VpnService.Builder — Flutter ↔ Android via MethodChannel.
class VpnServiceConfig {
  const VpnServiceConfig({
    required this.sessionName,
    required this.displayLabel,
    required this.outboundType,
    required this.mtu,
    required this.address,
    required this.addressPrefix,
    required this.routes,
    required this.dnsServers,
    required this.outboundServer,
    required this.outboundServerPort,
    required this.outboundUuid,
    required this.outboundFlow,
    required this.outboundTlsFingerprint,
    required this.outboundTlsSni,
    required this.outboundTlsPublicKey,
    required this.outboundTlsShortId,
    this.egressHosts = const [],
  });

  final String sessionName;
  final String displayLabel;
  final String outboundType;
  final int mtu;
  final String address;
  final int addressPrefix;
  final List<String> routes;
  final List<String> dnsServers;
  final String outboundServer;
  final int outboundServerPort;
  final String outboundUuid;
  final String? outboundFlow;
  final String? outboundTlsFingerprint;
  final String? outboundTlsSni;
  final String? outboundTlsPublicKey;
  final String? outboundTlsShortId;
  final List<String> egressHosts;

  /// Hosts that must stay off TUN via Android [excludeRoute].
  List<String> get controlPlaneHosts => controlPlaneHostsOf();

  /// Shared helper for Xray start and [VpnController.startTrustTunnel].
  static List<String> controlPlaneHostsOf() {
    final hosts = <String>{};
    try {
      final host = Uri.parse(AppConfig.baseUrl).host;
      if (host.isEmpty) {
        // keep empty
      } else if (RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(host)) {
        hosts.add(host);
      } else if (host == 'api.teremokconnect.online' ||
          host.endsWith('.teremokconnect.online')) {
        hosts.add(AppConfig.vpsIpv4);
      }
    } catch (_) {
      // ignore malformed baseUrl in tests
    }
    return hosts.toList();
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionName': sessionName,
      'displayLabel': displayLabel,
      'outboundType': outboundType,
      'mtu': mtu,
      'address': address,
      'addressPrefix': addressPrefix,
      'routes': routes,
      'dnsServers': dnsServers,
      'outboundServer': outboundServer,
      'outboundServerPort': outboundServerPort,
      'outboundUuid': outboundUuid,
      'outboundFlow': outboundFlow,
      'outboundTlsFingerprint': outboundTlsFingerprint,
      'outboundTlsSni': outboundTlsSni,
      'outboundTlsPublicKey': outboundTlsPublicKey,
      'outboundTlsShortId': outboundTlsShortId,
      'controlPlaneHosts': controlPlaneHosts,
      'egressHosts': egressHosts,
    };
  }

  String toJsonString() => jsonEncode(toMap());

  /// Single Xray JSON (legacy / diagnostics). Prefer [toJsonStringWithXrayCandidates].
  String toJsonStringWithXray(String xrayConfigJson) =>
      jsonEncode({
        ...toMap(),
        'schemaVersion': 2,
        'vpnCore': 'xray',
        'xrayConfigJson': xrayConfigJson,
      });

  /// Native sequential failover payload (one complete config per candidate).
  String toJsonStringWithXrayCandidates(
    List<XrayRuntimeCandidateConfig> candidates, {
    List<String> disallowedApplications = const [],
  }) =>
      jsonEncode({
        ...toMap(),
        'schemaVersion': 2,
        'vpnCore': 'xray',
        'xrayCandidateConfigs':
            candidates.map((c) => c.toMap()).toList(growable: false),
        if (disallowedApplications.isNotEmpty)
          'disallowedApplications': disallowedApplications,
      });

  /// Build TUN + outbound flat fields from [VpnConfig.xrayProfile].
  factory VpnServiceConfig.fromVpnConfig(
    VpnConfig config, {
    String? displayLabel,
  }) {
    final primary = config.primaryCandidate;
    const address = '10.255.255.1';
    const addressPrefix = 30;
    final routes = <String>['0.0.0.0/0'];
    final dnsServers = [tunDnsPeerAddress(address, addressPrefix)];

    return VpnServiceConfig(
      sessionName: kVpnBrandSessionName,
      displayLabel: resolveVpnDisplayLabel(config, displayLabel: displayLabel),
      outboundType: normalizeOutboundType(primary.protocol),
      mtu: 1500,
      address: address,
      addressPrefix: addressPrefix,
      routes: routes,
      dnsServers: dnsServers,
      outboundServer: primary.host,
      outboundServerPort: primary.port,
      outboundUuid: primary.uuid,
      outboundFlow: primary.flow,
      outboundTlsFingerprint: primary.fingerprint,
      outboundTlsSni: primary.serverName,
      outboundTlsPublicKey: primary.publicKey,
      outboundTlsShortId: primary.shortId,
      egressHosts: config.egressHosts,
    );
  }
}
