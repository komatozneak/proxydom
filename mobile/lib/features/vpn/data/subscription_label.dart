import 'dart:convert';

import '../../../core/utils/country_flags.dart';
import 'hy2_link_parser.dart';
import 'node_display.dart';
import 'share_link_parser.dart';

/// Neutral category mark drawn in front of a node. A subscription may name a
/// provider or a service; the app never ships that service's logo.
enum PoolTile { media, cloud, work, backup, flag }

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

  /// Flag emoji for country tiles. Empty for category tiles.
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
  // A provider's country tag is a location, not a name: `DE CompanyNet` draws
  // the German flag and the line is read as `CompanyNet`. The tag wins over the
  // host table because the provider knows the exit node it sold.
  final tag = countryTagFrom(split.$1);
  final title = tag?.title ?? split.$1;
  final tile = _tileForTitle(title);
  final host = link.endpoint.split(':').first;
  final place = placeForKnownHost(host);
  return PoolServerLabel(
    title: title,
    subtitle: split.$2,
    tile: tile,
    flag: tile == PoolTile.flag ? (tag?.flagEmoji ?? place?.flag ?? '') : '',
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
  if (lower.contains('youtube') ||
      lower.contains('медиа') ||
      lower.contains('media') ||
      lower.contains('video') ||
      lower.contains('stream')) {
    return PoolTile.media;
  }
  if (lower.contains('игров') ||
      lower.contains('gaming') ||
      lower.contains('cloud') ||
      lower.contains('облак') ||
      lower.contains('api')) {
    return PoolTile.cloud;
  }
  if (lower.contains('рабоч') ||
      lower.contains('work') ||
      lower.contains('офис') ||
      lower.contains('office')) {
    return PoolTile.work;
  }
  if (lower.contains('резерв') ||
      lower.contains('backup') ||
      lower.contains('запасн')) {
    return PoolTile.backup;
  }
  return PoolTile.flag;
}

/// Which mark a node's name earns, for anything that has a name and no label.
///
/// The profile list and the home screen show the same node, and the home used
/// to draw a globe for both: a category line had its own tile in the list and
/// a globe on the button. One name, one mark.
PoolTile tileForName(String title) => _tileForTitle(title);
