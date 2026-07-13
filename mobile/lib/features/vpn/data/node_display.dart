import 'vpn_node.dart';

/// Human-facing labels for Marzban nodes (ids like `node-185` are ops names).
class NodePlace {
  const NodePlace({
    required this.title,
    required this.subtitle,
    this.titleEn,
    this.subtitleEn,
    this.flag = '🌍',
  });

  final String title;
  final String subtitle;
  final String? titleEn;
  final String? subtitleEn;
  final String flag;

  String displayTitle(String languageCode) =>
      languageCode == 'en' && titleEn != null ? titleEn! : title;

  String displaySubtitle(String languageCode) =>
      languageCode == 'en' && subtitleEn != null ? subtitleEn! : subtitle;
}

/// Local map for known egress hosts. Edit when adding VPS / renaming in Marzban.
const Map<String, NodePlace> kKnownNodePlaces = {
  '185.139.228.192': NodePlace(
    title: 'Нидерланды',
    subtitle: 'Амстердам',
    titleEn: 'Netherlands',
    subtitleEn: 'Amsterdam',
    flag: '🇳🇱',
  ),
  '217.60.11.56': NodePlace(
    title: 'Германия',
    subtitle: 'Франкфурт',
    titleEn: 'Germany',
    subtitleEn: 'Frankfurt',
    flag: '🇩🇪',
  ),
  '45.91.248.91': NodePlace(
    title: 'США',
    subtitle: 'Нью-Йорк',
    titleEn: 'United States',
    subtitleEn: 'New York',
    flag: '🇺🇸',
  ),
};

/// Preference value: let backend / default pick the node.
const String kRegionAutoId = 'auto';

NodePlace placeForHost(String host, {int index = 0, String? fallbackLabel}) {
  final byHost = kKnownNodePlaces[host];
  if (byHost != null) return byHost;

  final raw = fallbackLabel?.trim() ?? '';
  if (raw.isNotEmpty &&
      !RegExp(r'^node[-_]?\d+$', caseSensitive: false).hasMatch(raw)) {
    return NodePlace(title: raw, subtitle: host, flag: '🌐');
  }
  return NodePlace(
    title: 'Сервер ${index + 1}',
    titleEn: 'Server ${index + 1}',
    subtitle: host,
    flag: '🌐',
  );
}

NodePlace placeForNode(VpnNode node, {int index = 0}) {
  final byHost = kKnownNodePlaces[node.host];
  if (byHost != null) return byHost;

  final raw = node.label.isNotEmpty
      ? node.label
      : (node.name.isNotEmpty ? node.name : node.host);
  // Skip ugly ops ids like node-185 when we have nothing better.
  if (RegExp(r'^node[-_]?\d+$', caseSensitive: false).hasMatch(raw.trim())) {
    return NodePlace(
      title: 'Сервер ${index + 1}',
      subtitle: node.host,
      flag: '🌐',
    );
  }
  return NodePlace(
    title: raw,
    subtitle: node.host,
    flag: '🌐',
  );
}
