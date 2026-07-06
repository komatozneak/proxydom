import 'dart:convert';

import 'vpn_config.dart';

/// Peer-адрес TUN (/30) для [VpnService.Builder.addDnsServer].
///
/// Android шлёт DNS на этот адрес внутри туннеля; sing-box перехватывает через hijack-dns.
String tunDnsPeerAddress(String address, int prefixLength) {
  final octets = address.split('.').map(int.parse).toList();
  if (octets.length != 4) return '172.19.0.2';

  final ip = (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];
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
  return '${(peer >> 24) & 0xff}.${(peer >> 16) & 0xff}.${(peer >> 8) & 0xff}.${peer & 0xff}';
}

/// Параметры для VpnService.Builder, извлечённые из sing-box config.
///
/// Используется для передачи между Flutter (Dart) и Android (Kotlin)
/// через MethodChannel (см. VpnController.start).
///
/// Сериализация в JSON-строку для обхода ограничений Bundle на вложенные Map
/// (Kotlin читает через org.json.JSONObject).
class VpnServiceConfig {
  const VpnServiceConfig({
    required this.sessionName,
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
  });

  /// Имя сессии для системного диалога ("Teremok VPN (username)").
  final String sessionName;

  /// MTU TUN-интерфейса (обычно 1500).
  final int mtu;

  /// IPv4 адрес TUN в нашей сети (например 10.255.255.1).
  final String address;

  /// Prefix length для адреса (например 30 для /30).
  final int addressPrefix;

  /// Список маршрутов в формате "address/prefix" (например ["0.0.0.0/0"]).
  /// Может включать и IPv6 маршруты (например ["::/0"]).
  final List<String> routes;

  /// DNS-серверы (например ["1.1.1.1", "8.8.8.8"]).
  final List<String> dnsServers;

  // === Outbound (proxy) parameters ===

  final String outboundServer;
  final int outboundServerPort;
  final String outboundUuid;
  final String? outboundFlow;

  /// uTLS fingerprint (например "chrome", "firefox", "safari").
  final String? outboundTlsFingerprint;

  /// TLS SNI — server name (например "example.com").
  final String? outboundTlsSni;

  /// Reality public key (X25519).
  final String? outboundTlsPublicKey;

  /// Reality short ID (hex).
  final String? outboundTlsShortId;

  /// Flat Map для MethodChannel.
  Map<String, dynamic> toMap() {
    return {
      'sessionName': sessionName,
      'mtu': mtu,
      'address': address,
      'addressPrefix': addressPrefix,
      'routes': routes,
      'dnsServers': dnsServers,
      // Flat outbound fields
      'outboundServer': outboundServer,
      'outboundServerPort': outboundServerPort,
      'outboundUuid': outboundUuid,
      'outboundFlow': outboundFlow,
      'outboundTlsFingerprint': outboundTlsFingerprint,
      'outboundTlsSni': outboundTlsSni,
      'outboundTlsPublicKey': outboundTlsPublicKey,
      'outboundTlsShortId': outboundTlsShortId,
    };
  }

  /// JSON-строка для MethodChannel (используется на этом шаге — проще
  /// передавать через Bundle, чем вложенный Map).
  String toJsonString() => jsonEncode(toMap());

  /// JSON с полным sing-box config для libbox (см. [buildRuntimeSingBoxJson]).
  String toJsonStringWithSingBox(String singBoxConfigJson) =>
      jsonEncode({...toMap(), 'singBoxConfigJson': singBoxConfigJson});

  /// Парсинг из VpnConfig + username.
  ///
  /// Приоритет:
  /// 1. Реальный inbound из sing-box JSON (если есть inet4_address)
  /// 2. Дефолты для dev/test
  factory VpnServiceConfig.fromVpnConfig(VpnConfig config) {
    final inbound = config.singBoxConfig.inbounds.isNotEmpty
        ? config.singBoxConfig.inbounds.first
        : null;
    final outbound = config.singBoxConfig.primaryOutbound;
    final tls = outbound?.tls;

    // Address: берём из inbound, иначе дефолт 10.255.255.1/30
    String address = '10.255.255.1';
    int addressPrefix = 30;
    if (inbound != null && inbound.inet4Address.isNotEmpty) {
      final parts = inbound.inet4Address.split('/');
      if (parts.length == 2) {
        address = parts[0];
        final parsedPrefix = int.tryParse(parts[1]);
        if (parsedPrefix != null) {
          addressPrefix = parsedPrefix;
        }
      } else {
        address = inbound.inet4Address;
      }
    }

    // Routes: дефолт "весь IPv4". IPv6 только если задан inet6_address —
    // иначе Android VpnService добавит ::/0 без v6-адреса и оборвёт интернет.
    final routes = <String>[];
    if (inbound == null || inbound.autoRoute) {
      routes.add('0.0.0.0/0');
    }
    final hasInet6 = inbound != null && inbound.inet6Address.isNotEmpty;
    if ((inbound?.strictRoute ?? false) && hasInet6) {
      routes.add('::/0');
    }
    if (routes.isEmpty) {
      routes.add('0.0.0.0/0'); // safety fallback
    }

    // DNS на peer TUN (/30): Android шлёт запросы в туннель → sing-box hijack-dns.
    final dnsServers = [tunDnsPeerAddress(address, addressPrefix)];

    return VpnServiceConfig(
      sessionName: 'Teremok VPN (${config.username})',
      mtu: 1500,
      address: address,
      addressPrefix: addressPrefix,
      routes: routes,
      dnsServers: dnsServers,
      outboundServer: outbound?.server ?? 'unknown',
      outboundServerPort: outbound?.serverPort ?? 443,
      outboundUuid: outbound?.uuid ?? '',
      outboundFlow: outbound?.flow,
      outboundTlsFingerprint: tls?.fingerprint,
      outboundTlsSni: tls?.serverName,
      outboundTlsPublicKey: tls?.publicKey,
      outboundTlsShortId: tls?.shortId,
    );
  }
}