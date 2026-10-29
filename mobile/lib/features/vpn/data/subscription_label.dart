import 'dart:convert';

import 'hy2_link_parser.dart';
import 'node_display.dart';
import 'share_link_parser.dart';

enum PoolTile { youtube, gaming, flag }

class PoolServerLabel {
  const PoolServerLabel({
    required this.title,
    required this.subtitle,
    required this.tile,
    required this.flag,
  });

  final String title;
  final String subtitle;
  final PoolTile tile;

  /// Flag emoji for country tiles. Empty for YouTube and gaming.
  final String flag;
}

/// Profile name from a `profile-title` header.
///
/// The value is plain text or base64. Remnawave prefixes the payload with
/// `base64:`. A prefixed value that does not decode is dropped so the raw
/// header is not shown as the list name.
String? decodeProfileTitle(String? header) {
  final raw = header?.trim();
  if (raw == null || raw.isEmpty) return null;
  final prefixed = raw.toLowerCase().startsWith('base64:');
  final payload = prefixed ? raw.substring(raw.indexOf(':') + 1).trim() : raw;
  if (payload.isEmpty) return prefixed ? null : raw;
  try {
    final decoded = utf8.decode(base64.decode(payload));
    if (decoded.trim().isNotEmpty) return decoded.trim();
  } on FormatException {
    if (prefixed) return null;
  }
  return prefixed ? null : raw;
}

/// First human-readable `# …` comment in a subscription body.
///
/// Known directive lines are not names. Without this, a body that starts with
/// `#proxydom-profile: <base64>` would show the encoded card as its title.
String? titleFromSubscriptionBody(String body) {
  for (final line in body.split(RegExp(r'\r?\n'))) {
    final text = line.trim();
    if (!text.startsWith('#') || text.startsWith('#?')) continue;
    final name = text.substring(1).trim();
    if (name.isEmpty) continue;
    final colon = name.indexOf(':');
    if (colon > 0) {
      final key = name.substring(0, colon).trim().toLowerCase();
      final value = name.substring(colon + 1).trim();
      if (key == 'profile-title') {
        final decoded = decodeProfileTitle(value);
        if (decoded != null && decoded.isNotEmpty) return decoded;
        return value.isEmpty ? null : value;
      }
      if (const {
        'proxydom-profile',
        'subscription-userinfo',
        'announce',
        'announce-frame',
        'support-url',
      }.contains(key)) {
        continue;
      }
    }
    return name;
  }
  return null;
}

PoolServerLabel labelForShareLink(ParsedShareLink link) {
  final split = _splitRemark(_remark(link));
  final tile = _tileForTitle(split.$1);
  final host = link.endpoint.split(':').first;
  final place = placeForKnownHost(host);
  return PoolServerLabel(
    title: split.$1,
    subtitle: split.$2,
    tile: tile,
    flag: tile == PoolTile.flag ? (place?.flag ?? '') : '',
  );
}

String _remark(ParsedShareLink link) {
  final decoded = decodedShareFragment(link.raw);
  if (decoded.isNotEmpty) return decoded;
  return link.name;
}

(String, String) _splitRemark(String name) {
  const sep = ' · ';
  final at = name.indexOf(sep);
  if (at < 0) return (name.trim(), '');
  return (name.substring(0, at).trim(), name.substring(at + sep.length).trim());
}

PoolTile _tileForTitle(String title) {
  final lower = title.toLowerCase();
  if (lower.contains('youtube')) return PoolTile.youtube;
  if (lower.contains('игров') || lower.contains('gaming')) {
    return PoolTile.gaming;
  }
  return PoolTile.flag;
}

/// Which mark a node's name earns, for anything that has a name and no label.
///
/// The profile list and the home screen show the same node, and the home used
/// to draw a globe for both: the YouTube line had its red tile in the list and
/// a globe on the button. One name, one mark.
PoolTile tileForName(String title) => _tileForTitle(title);

bool isPremiumPoolServer(String title) {
  final lower = title.toLowerCase();
  return lower.contains('youtube') ||
      lower.contains('игров') ||
      lower.contains('gaming') ||
      lower.contains('индия') ||
      lower.contains('india');
}
