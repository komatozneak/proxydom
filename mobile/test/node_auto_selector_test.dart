import 'package:flutter_test/flutter_test.dart';
import 'package:teremok_connect/features/vpn/data/node_auto_selector.dart';
import 'package:teremok_connect/features/vpn/data/node_display.dart';
import 'package:teremok_connect/features/vpn/data/vpn_node.dart';

VpnNode _node({
  required String id,
  required String label,
  String protocol = kVpnNodeProtocolVlessReality,
  String? purpose,
  bool requiresPremium = false,
  bool locked = false,
  String host = '204.11.2.216',
  bool connected = true,
}) {
  return VpnNode(
    id: id,
    label: label,
    host: host,
    port: 443,
    status: connected ? 'connected' : 'unknown',
    isDefault: false,
    protocol: protocol,
    purpose: purpose,
    requiresPremium: requiresPremium,
    locked: locked,
  );
}

void main() {
  final euRetired = _node(id: 'eu-primary', label: 'Восточная Европа');
  final us = _node(
    id: 'us-hy2-1',
    label: 'США · Бесплатно',
    purpose: 'geo-us',
    protocol: kVpnNodeProtocolHysteria2,
    host: '45.91.248.91',
  );
  final euFree = _node(
    id: 'eu-hy2-1',
    label: 'Европа · Бесплатно',
    protocol: kVpnNodeProtocolHysteria2,
    host: '217.60.3.9',
    purpose: 'general',
  );
  final gaming = _node(
    id: 'eu-gaming',
    label: 'Игровой · Premium',
    protocol: kVpnNodeProtocolHysteria2,
    purpose: 'gaming',
    requiresPremium: true,
    host: '204.11.2.216',
  );
  final youtube = _node(
    id: 'al-youtube',
    label: 'YouTube · Premium',
    protocol: kVpnNodeProtocolHysteria2,
    purpose: 'youtube',
    requiresPremium: true,
    host: '85.155.228.235',
  );
  final stub = _node(
    id: 'premium-youtube',
    label: 'Скоро',
    protocol: kVpnNodeProtocolTrusttunnel,
    purpose: 'coming_soon',
    requiresPremium: true,
    locked: true,
    host: '0.0.0.0',
  );

  final india = _node(
    id: 'in-geo-1',
    label: 'Индия · Premium',
    protocol: kVpnNodeProtocolHysteria2,
    purpose: 'geo-in',
    requiresPremium: true,
    host: '107.181.139.193',
  );

  test('Free Auto pool is EU then US Hy2, never TT / YouTube / eu-primary', () {
    final pool = autoPoolFor(
      [youtube, us, euFree, euRetired, gaming, stub, india],
      isPremium: false,
    );
    expect(pool.map((n) => n.id), ['eu-hy2-1', 'us-hy2-1']);
    expect(youtube.inAutoPool(isPremium: false), isFalse);
    expect(gaming.inAutoPool(isPremium: false), isFalse);
    expect(euRetired.inAutoPool(isPremium: false), isFalse);
    expect(india.inAutoPool(isPremium: false), isFalse);
    expect(euFree.isAutoEligible, isTrue);
    expect(autoPoolRank(euFree, isPremium: false), 0);
    expect(autoPoolRank(us, isPremium: false), 1);
    expect(autoPoolRank(gaming, isPremium: false), 3);
    expect(autoPoolRank(youtube, isPremium: false), 4);
  });

  test('Premium Auto pool tries YouTube first, then EU, US, gaming', () {
    final pool = autoPoolFor(
      [youtube, us, euFree, euRetired, gaming, india],
      isPremium: true,
    );
    expect(
      pool.map((n) => n.id),
      ['al-youtube', 'eu-hy2-1', 'us-hy2-1', 'eu-gaming'],
    );
    expect(gaming.inAutoPool(isPremium: true), isTrue);
    expect(youtube.inAutoPool(isPremium: true), isTrue);
    expect(euRetired.inAutoPool(isPremium: true), isFalse);
    expect(india.inAutoPool(isPremium: true), isFalse);
  });

  test('Premium Auto skips locked YouTube and uses other nodes', () {
    final lockedYt = _node(
      id: 'al-youtube',
      label: 'YouTube · Premium',
      protocol: kVpnNodeProtocolHysteria2,
      purpose: 'youtube',
      requiresPremium: true,
      locked: true,
      host: '85.155.228.235',
    );
    final pool = autoPoolFor(
      [lockedYt, us, euFree, gaming],
      isPremium: true,
    );
    expect(pool.map((n) => n.id), ['eu-hy2-1', 'us-hy2-1', 'eu-gaming']);
  });

  test('coming-soon stub and empty host never enter Auto', () {
    expect(stub.inAutoPool(isPremium: true), isFalse);
    expect(stub.inAutoPool(isPremium: false), isFalse);
  });

  test('autoCandidateHintLabel is short product copy', () {
    expect(autoCandidateHintLabel(us), 'США');
    expect(autoCandidateHintLabel(euFree), 'Латвия');
    expect(autoCandidateHintLabel(gaming), 'Игровой');
    expect(autoCandidateHintLabel(youtube), 'YouTube');
    expect(autoCandidateHintLabel(india), 'Индия');
    expect(autoCandidateHintLabel(us, languageCode: 'en'), 'USA');
    expect(autoCandidateHintLabel(euFree, languageCode: 'en'), 'Latvia');
    expect(autoCandidateHintLabel(gaming, languageCode: 'en'), 'Gaming');
    expect(autoCandidateHintLabel(us, languageCode: 'en'), isNot(contains('Free')));
    expect(autoCandidateHintLabel(us), isNot(contains('Бесплатно')));
  });

  test('resolveNodeIdForConfig keeps manual id (no Auto swap)', () {
    expect(
      resolveNodeIdForConfig(storedId: 'us-hy2-1', catalog: [us, euFree]),
      'us-hy2-1',
    );
    expect(
      resolveNodeIdForConfig(storedId: kRegionAutoId, catalog: [us, euFree]),
      isNull,
    );
    expect(
      resolveNodeIdForConfig(storedId: null, catalog: [us, euFree]),
      isNull,
    );
  });
}
