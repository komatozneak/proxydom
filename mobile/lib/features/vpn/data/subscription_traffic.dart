/// Traffic cap from a subscription document's `subscription-userinfo` header.
///
/// Bytes are `upload`, `download`, and `total`. A missing or zero `total`
/// means the document has no cap. One header covers the whole document.
class SubscriptionTraffic {
  const SubscriptionTraffic({
    required this.upload,
    required this.download,
    required this.total,
    this.expire,
  });

  final int upload;
  final int download;
  final int total;

  /// Absolute end of the plan, from `expire`. Null when the header omitted it.
  final DateTime? expire;

  /// `total <= 0` is the usual "no cap" signal in this header.
  bool get unlimited => total <= 0;

  /// Bytes still inside the cap. Never negative.
  int get remainingBytes {
    final left = total - upload - download;
    if (left < 0) return 0;
    return left;
  }
}

/// True when a document snapshot is stored. A blank value is not one:
/// the next refresh must still read the header.
bool hasTrafficSnapshot(String? meta) {
  final value = meta?.trim();
  return value != null && value.isNotEmpty;
}

/// A fresh header replaces the snapshot. A body that omits it does not.
///
/// Clearing happens when the document itself is dropped, not when a refresh
/// fails to repeat the header.
String? keptTrafficMeta({String? observed, String? saved}) {
  final next = observed?.trim();
  if (next != null && next.isNotEmpty) return next;
  final previous = saved?.trim();
  if (previous != null && previous.isNotEmpty) return previous;
  return null;
}

/// Header first, then a `#subscription-userinfo:` line in the body.
String? subscriptionTrafficMeta({String? header, String body = ''}) {
  final fromHeader = header?.trim();
  if (fromHeader != null && fromHeader.isNotEmpty) return fromHeader;
  for (final line in body.split(RegExp(r'\r?\n'))) {
    var text = line.trim();
    if (text.startsWith('#') && !text.startsWith('#?')) {
      text = text.substring(1).trim();
    }
    const key = 'subscription-userinfo';
    if (!text.toLowerCase().startsWith(key)) continue;
    final rest = text.substring(key.length).trim();
    if (!rest.startsWith(':')) continue;
    final value = rest.substring(1).trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

/// A list saved before the header was stored must not send `If-None-Match`.
/// A `304` would keep the missing cap forever.
String? etagUnlessTrafficUnknown({
  String? etag,
  required bool trafficKnown,
}) {
  if (!trafficKnown) return null;
  final value = etag?.trim();
  if (value == null || value.isEmpty) return null;
  return value;
}

/// Parses `upload=…; download=…; total=…; expire=…`. Unknown or broken text
/// is null; `expire` is seconds (or milliseconds when the value is large).
SubscriptionTraffic? parseSubscriptionTraffic(String? header) {
  if (header == null) return null;
  final text = header.trim();
  if (text.isEmpty) return null;
  int? upload;
  int? download;
  int? total;
  DateTime? expire;
  var sawField = false;
  for (final part in text.split(';')) {
    final piece = part.trim();
    final eq = piece.indexOf('=');
    if (eq <= 0) continue;
    final key = piece.substring(0, eq).trim().toLowerCase();
    final raw = piece.substring(eq + 1).trim();
    final value = int.tryParse(raw);
    if (value == null || value < 0) continue;
    if (key == 'upload') {
      upload = value;
      sawField = true;
    } else if (key == 'download') {
      download = value;
      sawField = true;
    } else if (key == 'total') {
      total = value;
      sawField = true;
    } else if (key == 'expire') {
      expire = _expireDate(value);
      sawField = true;
    }
  }
  if (!sawField) return null;
  return SubscriptionTraffic(
    upload: upload ?? 0,
    download: download ?? 0,
    total: total ?? 0,
    expire: expire,
  );
}

DateTime? _expireDate(int value) {
  if (value <= 0) return null;
  final millis = value >= 100000000000 ? value : value * 1000;
  return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}

const _tib = 1024 * 1024 * 1024 * 1024;
const _gib = 1024 * 1024 * 1024;
const _mib = 1024 * 1024;
const _mb = 1000 * 1000;
const _gb = 1000 * 1000 * 1000;
const _tb = 1000 * 1000 * 1000 * 1000;

/// Home pin bands for the remainder. Above 20 GiB is green, 5–20 is yellow,
/// below 5 is red. A missing header or an unlimited cap is not a band.
enum TrafficRemainderBand { above20, from5to20, below5, none }

TrafficRemainderBand trafficRemainderBand(SubscriptionTraffic? traffic) {
  if (traffic == null || traffic.unlimited) return TrafficRemainderBand.none;
  final left = traffic.remainingBytes;
  if (left > 20 * _gib) return TrafficRemainderBand.above20;
  if (left >= 5 * _gib) return TrafficRemainderBand.from5to20;
  return TrafficRemainderBand.below5;
}

/// Home pin value. No header is `—`, no cap is `∞`.
///
/// Legacy `subscription-userinfo` comes from panels that count in GiB, so the
/// default stays binary. A `proxydom-profile` manifest opts into the decimal
/// units it documents.
String formatSubscriptionTraffic(
  SubscriptionTraffic? traffic, {
  required bool russian,
  bool decimal = false,
}) {
  if (traffic == null) return '—';
  if (traffic.unlimited) return '∞';
  return _formatBytes(
    traffic.remainingBytes,
    russian: russian,
    decimal: decimal,
  );
}

/// A byte amount for the traffic bar's used/total labels.
String formatTrafficAmount(
  int bytes, {
  required bool russian,
  bool decimal = false,
}) {
  return _formatBytes(bytes, russian: russian, decimal: decimal);
}

String _formatBytes(
  int bytes, {
  required bool russian,
  required bool decimal,
}) {
  final gb = russian ? 'ГБ' : 'GB';
  final tb = russian ? 'ТБ' : 'TB';
  final mb = russian ? 'МБ' : 'MB';
  if (bytes <= 0) return '0 $mb';
  final tera = decimal ? _tb : _tib;
  final giga = decimal ? _gb : _gib;
  final mega = decimal ? _mb : _mib;
  if (bytes >= tera) {
    return _number(bytes / tera, tb, russian);
  }
  if (bytes >= giga) {
    return _number(bytes / giga, gb, russian);
  }
  if (bytes >= mega) {
    return _number(bytes / mega, mb, russian);
  }
  return '0 $mb';
}

String _number(double value, String unit, bool russian) {
  final digits = value >= 10 || value == value.roundToDouble() ? 0 : 1;
  final shown = value.toStringAsFixed(digits);
  final text = russian ? shown.replaceAll('.', ',') : shown;
  return '$text $unit';
}
