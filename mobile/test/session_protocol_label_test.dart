import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxydom/core/app_locale.dart';
import 'package:proxydom/features/vpn/data/vpn_service_config.dart';

void main() {
  test('imported share schemes keep their own label', () {
    expect(
      sessionProtocolLabel(selectedNodeProtocol: 'vless'),
      'VLESS',
    );
    expect(
      sessionProtocolLabel(selectedNodeProtocol: 'hysteria2'),
      'HYSTERIA2',
    );
  });

  test('Hy2 session is HYSTERIA2 not VLESS', () {
    expect(
      sessionProtocolLabel(
        selectedNodeProtocol: kDialSchemeHysteria2,
      ),
      'HYSTERIA2',
    );
  });

  test('TrustTunnel session is TRUSTTUNNEL', () {
    expect(
      sessionProtocolLabel(
        selectedNodeProtocol: kDialSchemeTrusttunnel,
      ),
      'TRUSTTUNNEL',
    );
  });

  test('connectedServerName uses the label the line carries', () {
    expect(
      connectedServerName(displayLabel: 'Латвия'),
      'Латвия',
    );
    expect(connectedServerName(), kVpnBrandSessionName);
  });

  test('connectedServerName drops · Бесплатно and localizes USA', () {
    AppLocale.set(const Locale('ru'));
    expect(
      connectedServerName(displayLabel: 'США · Бесплатно'),
      'США',
    );
    AppLocale.set(const Locale('en'));
    expect(
      connectedServerName(displayLabel: 'США · Бесплатно'),
      'USA',
    );
    expect(
      connectedServerName(displayLabel: 'США · Бесплатно'),
      isNot(contains('Free')),
    );
    AppLocale.set(const Locale('ru'));
  });
}
