/// Traffic cap from a subscription document's `subscription-userinfo` header.
///
/// Bytes are `upload`, `download`, and `total`. A missing or zero `total`
/// means the document has no cap. One header covers the whole document.
class SubscriptionTraffic {
  const SubscriptionTraffic({
    required this.upload,
    required this.download,
    required this.total,
  });

  final int upload;
  final int download;
  final int total;

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

/// Parses `upload=…; download=…; total=…`. Unknown or broken text is null.
SubscriptionTraffic? parseSubscriptionTraffic(String? header) {
  if (header == null) return null;
  final text = header.trim();
  if (text.isEmpty) return null;
  int? upload;
  int? download;
  int? total;
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
    }
  }
  if (!sawField) return null;
  return SubscriptionTraffic(
    upload: upload ?? 0,
    download: download ?? 0,
    total: total ?? 0,
  );
}

const _gib = 1024 * 1024 * 1024;
const _mib = 1024 * 1024;

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
/// 10 GiB and above is a whole number. Below that, one decimal. Below 0.1 GiB
/// the unit switches to MiB so a small remainder is not `0.0 GB`.
String formatSubscriptionTraffic(
  SubscriptionTraffic? traffic, {
  required bool russian,
}) {
  if (traffic == null) return '—';
  if (traffic.unlimited) return '∞';
  return _formatBytes(traffic.remainingBytes, russian: russian);
}

String _formatBytes(int bytes, {required bool russian}) {
  final gb = russian ? 'ГБ' : 'GB';
  final mb = russian ? 'МБ' : 'MB';
  if (bytes < _gib ~/ 10) {
    final whole = (bytes / _mib).round();
    return '$whole $mb';
  }
  final value = bytes / _gib;
  if (value >= 10) {
    return '${value.round()} $gb';
  }
  final shown = value.toStringAsFixed(1);
  final text = russian ? shown.replaceAll('.', ',') : shown;
  return '$text $gb';
}
