import 'dart:convert';

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

/// Profile name from a `profile-title` header. Happ sends it as base64.
String? decodeProfileTitle(String? header) {
  final raw = header?.trim();
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = utf8.decode(base64.decode(raw));
    if (decoded.trim().isNotEmpty) return decoded.trim();
  } on FormatException {
    // Plain text title.
  }
  return raw;
}

/// First `# Teremok VPN 🏠` comment in a subscription body.
String? titleFromSubscriptionBody(String body) {
  for (final line in body.split(RegExp(r'\r?\n'))) {
    final text = line.trim();
    if (!text.startsWith('#') || text.startsWith('#?')) continue;
    final name = text.substring(1).trim();
    if (name.isNotEmpty) return name;
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
  final hash = link.raw.indexOf('#');
  if (hash >= 0 && hash + 1 < link.raw.length) {
    final tail = link.raw.substring(hash + 1).trim();
    try {
      return Uri.decodeComponent(tail);
    } on ArgumentError {
      return tail;
    }
  }
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
