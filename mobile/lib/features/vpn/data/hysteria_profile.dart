/// Hysteria2 client profile. SOCKS prove on [socksListen].
///
/// Built from an `hy2://` / `hysteria2://` link by `Hy2LinkParser` and handed to
/// `VpnController.startHysteria`. This file is what remains of `vpn_config.dart`:
/// that file also held the account-era `VpnConfig` models of
/// `GET /api/v1/vpn/config`, which were removed because the local configurator
/// never constructs one.
class HysteriaProfile {
  const HysteriaProfile({
    required this.schemaVersion,
    required this.nodeId,
    required this.server,
    required this.auth,
    required this.username,
    required this.sni,
    required this.socksListen,
    this.bandwidthUp,
    this.bandwidthDown,
    this.congestion = '',
    this.bbrProfile = '',
    this.maxIdleTimeout = '',
    this.keepAlivePeriod = '',
    this.fmDeclared = '',
    this.insecure = false,
    this.obfs = '',
    this.obfsPassword = '',
  });

  final int schemaVersion;
  final String nodeId;
  final String server;
  final String auth;
  final String username;
  final String sni;
  final String socksListen;
  final String? bandwidthUp;
  final String? bandwidthDown;

  /// Controller name as written (`brutal`, `bbr`, `reno`). hy2bind decides
  /// what the engine is allowed to receive.
  final String congestion;

  /// BBR profile as written. Empty when the link did not name one.
  final String bbrProfile;

  /// QUIC timers in seconds, as declared. hy2bind clamps them.
  final String maxIdleTimeout;
  final String keepAlivePeriod;

  /// Names of `fm` fields that were present. Not their values.
  final String fmDeclared;

  /// Skip TLS verification. Share links set this with `insecure=1`.
  final bool insecure;

  /// Hysteria2 packet obfuscator, empty or `salamander`.
  final String obfs;
  final String obfsPassword;

  factory HysteriaProfile.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schema_version'] as int? ?? 1;
    if (schemaVersion != 1) {
      throw FormatException(
        'Unsupported hysteria_profile schema_version: $schemaVersion',
      );
    }
    final server = (json['server'] as String? ?? '').trim();
    final auth = (json['auth'] as String? ?? '').trim();
    if (server.isEmpty || auth.isEmpty) {
      throw const FormatException('Incomplete hysteria_profile');
    }
    return HysteriaProfile(
      schemaVersion: schemaVersion,
      nodeId: json['node_id'] as String? ?? '',
      server: server,
      auth: auth,
      username: json['username'] as String? ?? '',
      sni: json['sni'] as String? ?? '',
      socksListen: json['socks_listen'] as String? ?? '127.0.0.1:10808',
      bandwidthUp: json['bandwidth_up'] as String?,
      bandwidthDown: json['bandwidth_down'] as String?,
      congestion: json['congestion'] as String? ?? '',
      bbrProfile: json['bbr_profile'] as String? ?? '',
      maxIdleTimeout: json['max_idle_timeout'] as String? ?? '',
      keepAlivePeriod: json['keep_alive_period'] as String? ?? '',
      fmDeclared: json['fm_declared'] as String? ?? '',
      insecure: json['insecure'] == true,
      obfs: json['obfs'] as String? ?? '',
      obfsPassword: json['obfs_password'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'node_id': nodeId,
        'server': server,
        'auth': auth,
        'username': username,
        'sni': sni,
        'socks_listen': socksListen,
        if (bandwidthUp != null) 'bandwidth_up': bandwidthUp,
        if (bandwidthDown != null) 'bandwidth_down': bandwidthDown,
        if (congestion.isNotEmpty) 'congestion': congestion,
        if (bbrProfile.isNotEmpty) 'bbr_profile': bbrProfile,
        if (maxIdleTimeout.isNotEmpty) 'max_idle_timeout': maxIdleTimeout,
        if (keepAlivePeriod.isNotEmpty) 'keep_alive_period': keepAlivePeriod,
        if (fmDeclared.isNotEmpty) 'fm_declared': fmDeclared,
        if (insecure) 'insecure': true,
        if (obfs.isNotEmpty) 'obfs': obfs,
        if (obfsPassword.isNotEmpty) 'obfs_password': obfsPassword,
      };
}
