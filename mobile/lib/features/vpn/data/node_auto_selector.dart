import 'node_display.dart';
import 'vpn_node.dart';

/// Ordered Auto pool (ADR 015 / honest prove).
///
/// Free: EU Hy2 → US Hy2.
/// Premium: Free pool then gaming TT then YouTube TT.
/// SOCKS CONNECT :443 through the tunnel — not Cloudflare generate_204.
List<VpnNode> autoPoolFor(
  Iterable<VpnNode> catalog, {
  required bool isPremium,
}) {
  final pool = catalog.where((n) => n.inAutoPool(isPremium: isPremium)).toList();
  pool.sort((a, b) {
    final ra = autoPoolRank(a);
    final rb = autoPoolRank(b);
    if (ra != rb) return ra.compareTo(rb);
    final la = a.label.isNotEmpty ? a.label : a.id;
    final lb = b.label.isNotEmpty ? b.label : b.id;
    return la.toLowerCase().compareTo(lb.toLowerCase());
  });
  return pool;
}

/// EU Free Hy2 → US Hy2 → gaming TT → YouTube. Not RTT.
int autoPoolRank(VpnNode node) {
  if (node.isYoutube) return 4;
  if (node.isGaming) return 3;
  if (node.isGeoUs) return 1;
  return 0;
}

/// Short Auto status label: США / Европа / Игровой / YouTube.
String autoCandidateHintLabel(VpnNode node) {
  if (node.isYoutube) return 'YouTube';
  if (node.isGaming) return 'Игровой';
  if (node.isGeoUs) return 'США';
  if (node.isHysteria) return 'Европа';
  final label = node.label.isNotEmpty ? node.label : node.id;
  final lower = label.toLowerCase();
  if (lower.contains('youtube')) return 'YouTube';
  if (lower.contains('игров') || lower.contains('gaming')) return 'Игровой';
  if (lower.contains('европ') || lower.contains('europe')) {
    return 'Европа';
  }
  if (lower.contains('сша') || lower.contains('usa')) {
    return 'США';
  }
  return label;
}

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
