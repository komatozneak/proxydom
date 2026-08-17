import 'node_display.dart';
import 'vpn_node.dart';

/// Ordered Auto pool (ADR 015 / honest prove).
///
/// Free: EU Hy2 → US Hy2.
/// Premium: YouTube (if unlocked) → EU Hy2 → US Hy2 → gaming.
/// SOCKS CONNECT :443 through the tunnel — not Cloudflare generate_204.
List<VpnNode> autoPoolFor(
  Iterable<VpnNode> catalog, {
  required bool isPremium,
}) {
  final pool = catalog.where((n) => n.inAutoPool(isPremium: isPremium)).toList();
  pool.sort((a, b) {
    final ra = autoPoolRank(a, isPremium: isPremium);
    final rb = autoPoolRank(b, isPremium: isPremium);
    if (ra != rb) return ra.compareTo(rb);
    final la = a.label.isNotEmpty ? a.label : a.id;
    final lb = b.label.isNotEmpty ? b.label : b.id;
    return la.toLowerCase().compareTo(lb.toLowerCase());
  });
  return pool;
}

/// Free: EU → US. Premium: YouTube first, then the rest. India geo never Auto.
int autoPoolRank(VpnNode node, {required bool isPremium}) {
  if (node.isGeoIn) return 99;
  if (isPremium) {
    if (node.isYoutube) return 0;
    if (node.isGaming) return 3;
    if (node.isGeoUs) return 2;
    return 1;
  }
  if (node.isYoutube) return 4;
  if (node.isGaming) return 3;
  if (node.isGeoUs) return 1;
  return 0;
}

/// Short Auto status label — same titles as Locations (`placeForNode`).
String autoCandidateHintLabel(VpnNode node, {String languageCode = 'ru'}) =>
    placeForNode(node).displayTitle(languageCode);

/// Manual Locations id, or null when the user chose Auto (engine prove loop).
String? resolveNodeIdForConfig({
  required String? storedId,
  required List<VpnNode> catalog,
}) {
  if (storedId == null || storedId.isEmpty || storedId == kRegionAutoId) {
    return null;
  }
  final exists = catalog.any((n) => n.id == storedId);
  return exists ? storedId : storedId;
}
