import '../../features/home/data/external_ip_service.dart';

/// Result of egress IP probe while VPN may be active.
class EgressVerifyResult {
  const EgressVerifyResult({
    required this.externalIp,
    required this.expectedHost,
    required this.egressOk,
  });

  final String? externalIp;
  final String? expectedHost;

  /// `true` / `false` when IP fetched; `null` when IP unavailable.
  final bool? egressOk;

  String get externalIpLabel => externalIp ?? '(unavailable)';

  String get egressOkLabel {
    if (egressOk == null) return 'unknown';
    return egressOk! ? 'true' : 'false';
  }
}

/// IP↔IP vs catalog host. Hostname/SNI and Hy2 NAT (catalog ≠ icanhazip)
/// are not a tunnel-dead gate — only exact IPv4 equality is `match`.
String egressCheckLabel({
  required String? externalIp,
  required String? catalogHost,
}) {
  final ip = externalIp?.trim();
  final host = catalogHost?.trim();
  if (ip == null || ip.isEmpty || host == null || host.isEmpty) {
    return 'inconclusive';
  }
  if (!_looksLikeIpv4(host)) return 'inconclusive';
  if (ip == host) return 'match';
  return 'nat';
}

bool _looksLikeIpv4(String value) {
  return RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(value);
}

Future<EgressVerifyResult> verifyEgress({String? expectedHost}) async {
  final ip = await fetchExternalIp();
  if (ip == null) {
    return EgressVerifyResult(
      externalIp: null,
      expectedHost: expectedHost,
      egressOk: null,
    );
  }
  final host = expectedHost?.trim();
  if (host == null || host.isEmpty) {
    return EgressVerifyResult(
      externalIp: ip,
      expectedHost: null,
      egressOk: null,
    );
  }
  // Hostname or NAT egress ≠ inbound/catalog IP is not a failed tunnel.
  if (!_looksLikeIpv4(host) || ip != host) {
    return EgressVerifyResult(
      externalIp: ip,
      expectedHost: host,
      egressOk: null,
    );
  }
  return EgressVerifyResult(
    externalIp: ip,
    expectedHost: host,
    egressOk: true,
  );
}
