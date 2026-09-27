import '../../../core/config.dart';

import 'subscription_label.dart';
import 'subscription_traffic.dart';

/// Happ announcement limit. Longer text is cut before it is shown or sent.
const subscriptionAnnounceLimit = 200;

/// One key description: the text, the Telegram plane, and the rounded frame.
///
/// Happ reads this as `announce` plus `support-url`. The frame is how that
/// announcement is drawn. Markers in the source text ask for the same pieces:
///
/// - `{{frame}}...{{/frame}}` — rounded border
/// - `{{plane}}` or `{{plane:https://t.me/name}}` — paper plane
class SubscriptionNotice {
  const SubscriptionNotice({
    this.text,
    this.planeUrl,
    this.frame = false,
  });

  final String? text;
  final String? planeUrl;
  final bool frame;

  bool get visible {
    final body = text?.trim() ?? '';
    final plane = planeUrl?.trim() ?? '';
    return body.isNotEmpty || plane.isNotEmpty;
  }
}

/// Authoring tool. [frame] and [planeUrl] add the border and the plane.
/// Markers inside [text] do the same. A foreign Happ announcement is read
/// with [subscriptionNotice], which frames any announcement by default.
SubscriptionNotice composeKeyDescription(
  String text, {
  String? planeUrl,
  bool frame = false,
}) {
  final marked = _applyMarkers(text);
  final plane = _httpUrl(planeUrl) ?? _httpUrl(marked.planeUrl);
  final body = _clip(marked.text);
  final showFrame = body.isNotEmpty && (frame || marked.framed);
  return SubscriptionNotice(
    text: body.isEmpty ? null : body,
    planeUrl: plane,
    frame: showFrame,
  );
}

/// Header values win. Body `#announce:` / `#support-url:` fill the gaps.
/// An announcement without `announce-frame: 0` is framed, matching Happ.
SubscriptionNotice subscriptionNotice({
  String? announceHeader,
  String? supportHeader,
  String? frameHeader,
  String body = '',
}) {
  final fields = subscriptionBodyFields(body);
  final decoded = decodeProfileTitle(
    _first(announceHeader, fields['announce']),
  );
  final marked = _applyMarkers(decoded ?? '');
  final plane = _httpUrl(_first(supportHeader, fields['support-url'])) ??
      _httpUrl(marked.planeUrl);
  final text = _clip(marked.text);
  final frame = _frameFlag(
    _first(frameHeader, fields['announce-frame']),
    marked: marked.framed,
    hasText: text.isNotEmpty,
  );
  return SubscriptionNotice(
    text: text.isEmpty ? null : text,
    planeUrl: plane,
    frame: frame && text.isNotEmpty,
  );
}

/// `#support-url:` and `#announce:` lines. A title comment without `:` is not one.
Map<String, String> subscriptionBodyFields(String body) {
  final out = <String, String>{};
  final line = RegExp(r'^#([A-Za-z0-9-]+):\s*(.*)$');
  for (final raw in body.split(RegExp(r'\r?\n'))) {
    final match = line.firstMatch(raw.trim());
    if (match == null) continue;
    final key = match.group(1)!.toLowerCase();
    final value = match.group(2)!.trim();
    if (value.isEmpty || out.containsKey(key)) continue;
    out[key] = value;
  }
  return out;
}

/// Telegram hosts get the paper plane. Any other http(s) link is a plain link.
bool subscriptionPlaneIsTelegram(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  return host == 't.me' || host == 'telegram.me' || host == 'telegram.dog';
}

String? _first(String? header, String? fromBody) {
  final primary = header?.trim();
  if (primary != null && primary.isNotEmpty) return primary;
  final secondary = fromBody?.trim();
  if (secondary != null && secondary.isNotEmpty) return secondary;
  return null;
}

bool _frameFlag(
  String? explicit, {
  required bool marked,
  required bool hasText,
}) {
  final flag = explicit?.trim().toLowerCase();
  if (flag == '0' || flag == 'false') return false;
  if (flag == '1' || flag == 'true') return true;
  if (marked) return true;
  return hasText;
}

class _Marked {
  const _Marked({required this.text, this.planeUrl, required this.framed});

  final String text;
  final String? planeUrl;
  final bool framed;
}

_Marked _applyMarkers(String text) {
  String? plane;
  final planeRe = RegExp(r'\{\{plane(?::([^}]*))?\}\}');
  final withoutPlane = text.replaceAllMapped(planeRe, (match) {
    final found = match.group(1)?.trim();
    if (plane == null && found != null && found.isNotEmpty) plane = found;
    return '';
  });
  final framed = text.contains('{{frame}}');
  final cleaned = withoutPlane.replaceAll(RegExp(r'\{\{/?frame\}\}'), '');
  final lines = <String>[];
  for (final raw in cleaned.split(RegExp(r'\r?\n'))) {
    final line = raw.split(RegExp(r'[ \t]+')).join(' ').trim();
    if (line.isNotEmpty) lines.add(line);
  }
  return _Marked(text: lines.join('\n'), planeUrl: plane, framed: framed);
}

String _clip(String text) {
  final trimmed = text.trim();
  final units = trimmed.runes.toList();
  if (units.length <= subscriptionAnnounceLimit) return trimmed;
  return String.fromCharCodes(units.take(subscriptionAnnounceLimit))
      .trimRight();
}

String? _httpUrl(String? value) {
  final url = value?.trim();
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  if (uri.host.isEmpty) return null;
  return url;
}

/// Paper plane for the Teremok VPN bot.
String teremokBotUrl() {
  final name =
      AppConfig.telegramBotUsername.trim().replaceFirst(RegExp(r'^@'), '');
  return 'https://t.me/$name';
}

/// ``🗓️ Ещё 5 дней``. Zero is the expiry date itself.
String daysLeftLine(int days) {
  final count = days < 0 ? 0 : days;
  if (count == 0) return '🗓️ Последний день';
  return '🗓️ Ещё $count ${_dayWord(count)}';
}

/// What the profile card shows. A document announcement wins. A new link
/// with none still gets the Teremok VPN note and the bot plane.
SubscriptionNotice profileNotice({
  String? announce,
  String? supportUrl,
  bool announceFrame = false,
  String? documentUrl,
  String? trafficMeta,
  DateTime? now,
}) {
  final remote = announce?.trim();
  if (remote != null && remote.isNotEmpty) {
    final plane = _httpUrl(supportUrl) ?? teremokBotUrl();
    return SubscriptionNotice(
      text: remote,
      planeUrl: plane,
      frame: announceFrame,
    );
  }
  final clock = (now ?? DateTime.now()).toUtc();
  final traffic = parseSubscriptionTraffic(trafficMeta);
  final active =
      traffic == null || traffic.unlimited || traffic.remainingBytes > 0;
  final expire = _expireUnix(trafficMeta);
  final days = expire == null ? null : _calendarDays(expire, clock);
  return composeKeyDescription(
    _teremokCopy(
      code: _publicCode(documentUrl),
      active: active,
      days: days,
    ),
    planeUrl: teremokBotUrl(),
    frame: true,
  );
}

String _teremokCopy({
  required String? code,
  required bool active,
  required int? days,
}) {
  final lines = <String>['Значок справа ведёт в бота'];
  if (code != null) {
    lines.add('🔑 $code ${active ? 'Active' : 'Пауза'}');
  }
  if (days != null) lines.add(daysLeftLine(days));
  lines.add('◻️ Молчит? Жми 🔄');
  lines.add('❤️ Теремок VPN');
  return lines.join('\n');
}

String? _publicCode(String? url) {
  final uri = Uri.tryParse(url ?? '');
  if (uri == null) return null;
  final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  final clean = parts.last.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (clean.length < 8) return null;
  return clean.substring(0, 8);
}

int? _expireUnix(String? header) {
  if (header == null) return null;
  for (final part in header.split(';')) {
    final piece = part.trim();
    final eq = piece.indexOf('=');
    if (eq <= 0) continue;
    if (piece.substring(0, eq).trim().toLowerCase() != 'expire') continue;
    final value = int.tryParse(piece.substring(eq + 1).trim());
    if (value == null || value <= 0) return null;
    return value;
  }
  return null;
}

int _calendarDays(int expireUnix, DateTime now) {
  final end =
      DateTime.fromMillisecondsSinceEpoch(expireUnix * 1000, isUtc: true);
  final today = DateTime.utc(now.year, now.month, now.day);
  final last = DateTime.utc(end.year, end.month, end.day);
  final days = last.difference(today).inDays;
  return days < 0 ? 0 : days;
}

String _dayWord(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) return 'день';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'дня';
  return 'дней';
}
