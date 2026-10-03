import 'subscription_label.dart';

/// Happ announcement limit. Longer text is cut before it is shown or sent.
const subscriptionAnnounceLimit = 200;

/// One key description: the text, the Telegram plane, and the rounded frame.
///
/// Happ reads this as `announce` plus `support-url`. The frame is how that
/// announcement is drawn. Markers in the source text ask for the same pieces:
///
/// - `{{frame}}...{{/frame}}` — rounded border
/// - `{{plane}}` or `{{plane:<address>}}` — paper plane
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

/// What the profile card shows. Text and the plane come only from the link.
/// An empty announcement leaves the slot blank. This screen does not draw
/// the Happ frame.
SubscriptionNotice profileNotice({
  String? announce,
  String? supportUrl,
}) {
  final body = _clip(announce ?? '');
  return SubscriptionNotice(
    text: body.isEmpty ? null : body,
    planeUrl: _httpUrl(supportUrl),
    frame: false,
  );
}
