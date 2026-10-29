import 'dart:convert';

import 'subscription_notice.dart';

/// A hoster-authored profile card carried inside a subscription response.
///
/// The wire value is UTF-8 JSON in base64url. The parser is deliberately
/// stricter than the legacy headers: a bad manifest is ignored as a whole so
/// the client can keep the old fields, but a bad optional field only loses
/// that field.
class ProfileManifest {
  const ProfileManifest({
    required this.version,
    this.displayName,
    this.description,
    this.supportUrl,
    this.supportLabel,
    this.planName,
    this.accent,
    this.traffic,
  });

  final int version;
  final String? displayName;
  final String? description;
  final String? supportUrl;
  final String? supportLabel;
  final String? planName;

  /// `#RRGGBB`, currently parsed and stored but not used by the palette.
  final String? accent;

  final ProfileTraffic? traffic;

  Map<String, Object?> toJson() => {
        'version': version,
        if (displayName != null) 'displayName': displayName,
        if (description != null) 'description': description,
        if (supportUrl != null) 'supportUrl': supportUrl,
        if (supportLabel != null) 'supportLabel': supportLabel,
        if (planName != null) 'planName': planName,
        if (accent != null) 'accent': accent,
        if (traffic != null) 'traffic': traffic!.toJson(),
      };

  /// Reads a stored manifest map, not a wire base64 value.
  static ProfileManifest? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return _parseObject(Map<String, dynamic>.from(raw));
  }
}

/// The manifest's quota snapshot. Missing is not zero.
class ProfileTraffic {
  const ProfileTraffic({
    this.upload = 0,
    this.download = 0,
    this.total,
    this.unlimited = false,
    this.resetAt,
    this.expiresAt,
    this.updatedAt,
    this.fairUseNote,
  });

  final int upload;
  final int download;
  final int? total;
  final bool unlimited;
  final DateTime? resetAt;
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final String? fairUseNote;

  int get usedBytes => upload + download;

  Map<String, Object?> toJson() => {
        'upload': upload,
        'download': download,
        if (total != null) 'total': total,
        if (unlimited) 'unlimited': true,
        if (resetAt != null) 'resetAt': resetAt!.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (fairUseNote != null) 'fairUseNote': fairUseNote,
      };
}

/// A raw header value is taken seriously even when it is broken: the body is
/// only consulted when the header is absent, so a bad header cannot be
/// replaced by a stale body copy.
ProfileManifest? profileManifestFromResponse({
  String? header,
  String body = '',
}) {
  final rawHeader = header?.trim();
  if (rawHeader != null && rawHeader.isNotEmpty) {
    return decodeProfileManifest(rawHeader);
  }
  final fields = subscriptionBodyFields(body);
  for (final entry in fields.entries) {
    if (entry.key.toLowerCase() == 'proxydom-profile') {
      return decodeProfileManifest(entry.value);
    }
  }
  return null;
}

/// Decodes a base64url JSON value. Returns null for anything that is not a
/// complete, bounded v1-or-later object.
ProfileManifest? decodeProfileManifest(String? encoded) {
  final raw = encoded?.trim();
  if (raw == null || raw.isEmpty || raw.length > 2732) return null;
  if (raw.toLowerCase().startsWith('base64:')) return null;
  if (RegExp(r'\s').hasMatch(raw)) return null;

  final normalized = raw.replaceAll('-', '+').replaceAll('_', '/');
  final padded = normalized.length % 4 == 0
      ? normalized
      : normalized.padRight(
          normalized.length + (4 - normalized.length % 4),
          '=',
        );
  final List<int> bytes;
  try {
    bytes = base64.decode(padded);
  } on FormatException {
    return null;
  }
  if (bytes.length > 2048) return null;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return null;
  }

  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  return _parseObject(Map<String, dynamic>.from(decoded));
}

ProfileManifest? _parseObject(Map<String, dynamic> json) {
  if (!_boundedShape(json)) return null;
  final version = json['version'];
  if (version is! int || version < 1) return null;

  final traffic = _parseTraffic(json['traffic']);
  return ProfileManifest(
    version: version,
    displayName: _cleanText(json['displayName'], max: 40),
    description: _cleanText(json['description'], max: 200, multiline: true),
    supportUrl: _httpsUrl(json['supportUrl']),
    supportLabel: _cleanText(json['supportLabel'], max: 24),
    planName: _cleanText(json['planName'], max: 24),
    accent: _accent(json['accent']),
    traffic: traffic,
  );
}

/// At most 16 unknown keys and no nesting deeper than four.
bool _boundedShape(Object? raw, {int depth = 0, int unknown = 0}) {
  if (depth > 4) return false;
  if (raw is Map) {
    var nextUnknown = unknown;
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      const known = {
        'version',
        'displayName',
        'description',
        'supportUrl',
        'supportLabel',
        'planName',
        'accent',
        'traffic',
        'upload',
        'download',
        'total',
        'unlimited',
        'resetAt',
        'expiresAt',
        'fairUseNote',
        'updatedAt',
      };
      if (!known.contains(key)) nextUnknown++;
      if (nextUnknown > 16) return false;
      if (!_boundedShape(entry.value, depth: depth + 1, unknown: nextUnknown)) {
        return false;
      }
    }
  } else if (raw is List) {
    for (final item in raw) {
      if (!_boundedShape(item, depth: depth + 1, unknown: unknown)) {
        return false;
      }
    }
  }
  return true;
}

ProfileTraffic? _parseTraffic(Object? raw) {
  if (raw is! Map) return null;
  final map = Map<String, dynamic>.from(raw);
  final upload = _byteCount(map, 'upload');
  final download = _byteCount(map, 'download');
  final total = _byteCount(map, 'total');
  final unlimited = map['unlimited'];
  if (map.containsKey('upload') && upload == null) return null;
  if (map.containsKey('download') && download == null) return null;
  if (map.containsKey('total') && total == null) return null;
  if (unlimited != null && unlimited is! bool) return null;

  final resetAt = _dateTime(map['resetAt']);
  final expiresAt = _dateTime(map['expiresAt']);
  final updatedAt = _dateTime(map['updatedAt']);
  final fairUseNote = _cleanText(map['fairUseNote'], max: 120);
  final hasNumbers = upload != null ||
      download != null ||
      total != null ||
      unlimited == true ||
      resetAt != null ||
      expiresAt != null ||
      updatedAt != null ||
      fairUseNote != null;
  if (!hasNumbers) return null;

  return ProfileTraffic(
    upload: upload ?? 0,
    download: download ?? 0,
    total: total,
    unlimited: unlimited == true,
    resetAt: resetAt,
    expiresAt: expiresAt,
    updatedAt: updatedAt,
    fairUseNote: fairUseNote,
  );
}

int? _byteCount(Map<String, dynamic> map, String key) {
  if (!map.containsKey(key)) return null;
  final value = map[key];
  if (value is! int || value < 0 || value > 1000000000000000000) {
    return null;
  }
  return value;
}

DateTime? _dateTime(Object? raw) {
  if (raw is! String) return null;
  final text = raw.trim();
  if (text.isEmpty) return null;
  // Dart's tryParse also accepts a naive local time; the manifest requires an
  // explicit offset so the hoster's timezone is never guessed.
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(text)) return null;
  final parsed = DateTime.tryParse(text);
  return parsed?.toUtc();
}

String? _cleanText(
  Object? raw, {
  required int max,
  bool multiline = false,
}) {
  if (raw is! String) return null;
  var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  text = text.replaceAll(
    RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'),
    '',
  );
  if (!multiline) {
    text = text.replaceAll(RegExp(r'\s*\n+\s*'), ' ');
  } else {
    final lines = text.split('\n').map((line) => line.trim()).toList();
    if (lines.length > 2) text = '${lines[0]}\n${lines[1]}';
  }
  final scalars = text.runes.toList();
  if (scalars.length > max) {
    text = String.fromCharCodes(scalars.take(max)).trimRight();
  }
  return text.isEmpty ? null : text;
}

String? _httpsUrl(Object? raw) {
  final text = _cleanText(raw, max: 200);
  if (text == null) return null;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return text;
}

String? _accent(Object? raw) {
  if (raw is! String) return null;
  final text = raw.trim();
  return RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(text) ? text : null;
}
