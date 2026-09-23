import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/core/app_locale.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';
import 'package:teremok_connect/features/vpn/data/vpn_service_config.dart';

void main() {
  test('imported share schemes keep their own label', () {
    expect(
      sessionProtocolLabel(config: null, selectedNodeProtocol: 'vless'),
      'VLESS',
    );
    expect(
      sessionProtocolLabel(config: null, selectedNodeProtocol: 'hysteria2'),
      'HYSTERIA2',
    );
  });

  test('Hy2 session is HYSTERIA2 not VLESS', () {
    expect(
      sessionProtocolLabel(
        config: null,
        selectedNodeProtocol: kVpnNodeProtocolHysteria2,
      ),
      'HYSTERIA2',
    );
  });

  test('TrustTunnel session is TRUSTTUNNEL', () {
    expect(
      sessionProtocolLabel(
        config: null,
        selectedNodeProtocol: kVpnNodeProtocolTrusttunnel,
      ),
      'TRUSTTUNNEL',
    );
  });

  test('connectedServerName uses catalog label without a live config', () {
    expect(
      connectedServerName(config: null, displayLabel: 'Латвия'),
      'Латвия',
    );
    expect(connectedServerName(config: null), kVpnBrandSessionName);
  });

  test('connectedServerName drops · Бесплатно and localizes USA', () {
    AppLocale.set(const Locale('ru'));
    expect(
      connectedServerName(config: null, displayLabel: 'США · Бесплатно'),
      'США',
    );
    AppLocale.set(const Locale('en'));
    expect(
      connectedServerName(config: null, displayLabel: 'США · Бесплатно'),
      'USA',
    );
    expect(
      connectedServerName(config: null, displayLabel: 'США · Бесплатно'),
      isNot(contains('Free')),
    );
    AppLocale.set(const Locale('ru'));
  });
}
