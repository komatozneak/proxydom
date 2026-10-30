/// Country markers providers put in front of node names.
///
/// A subscription line is often named `DE DoDoVPN | Hysteria` or
/// `🇩🇪 DoDoVPN | Hysteria`. The marker is a location, not part of the name:
/// the list draws it as the country's flag and the rest is what the person
/// reads. Parsing is prefix-only on purpose — `WS` in
/// `DoDoVPN | WS | Резерв` is a transport, and reading it as Samoa would put
/// the wrong flag on the line.
library;

/// A country marker taken off the front of a name.
class CountryTag {
  const CountryTag({required this.code, required this.title});

  /// Lowercase flag asset key, e.g. `de`, `gb`, `eu`.
  final String code;

  /// The name without the marker. Falls back to the original when the marker
  /// was the whole name — an empty title is worse than a redundant `DE`.
  final String title;

  /// Flag emoji for the country, e.g. `🇩🇪`.
  String? get flagEmoji => flagEmojiForCountryCode(code);
}

/// Two-letter codes that have a flag in `assets/flags/`.
///
/// Kept to what the bundle ships: a code with no SVG would win a flag and
/// leave an empty tile. `eu` is the one non-country key the directory has.
const Set<String> kCountryFlagCodes = {
  'ae',
  'af',
  'ag',
  'ai',
  'al',
  'am',
  'ao',
  'ar',
  'at',
  'au',
  'aw',
  'ax',
  'az',
  'ba',
  'bb',
  'bd',
  'be',
  'bf',
  'bg',
  'bh',
  'bi',
  'bj',
  'bl',
  'bn',
  'br',
  'bs',
  'bv',
  'bw',
  'by',
  'ca',
  'cc',
  'cd',
  'cf',
  'cg',
  'ch',
  'ci',
  'ck',
  'cl',
  'cm',
  'cn',
  'co',
  'cr',
  'cu',
  'cv',
  'cw',
  'cx',
  'cy',
  'cz',
  'de',
  'dj',
  'dk',
  'dm',
  'dz',
  'ee',
  'eg',
  'er',
  'et',
  'eu',
  'fi',
  'fm',
  'fo',
  'fr',
  'ga',
  'gb',
  'gd',
  'ge',
  'gf',
  'gg',
  'gh',
  'gi',
  'gl',
  'gm',
  'gn',
  'gp',
  'gq',
  'gr',
  'gu',
  'gw',
  'gy',
  'hk',
  'hm',
  'hn',
  'ht',
  'hu',
  'id',
  'ie',
  'il',
  'im',
  'in',
  'iq',
  'ir',
  'is',
  'it',
  'jm',
  'jo',
  'jp',
  'ke',
  'kg',
  'kh',
  'ki',
  'km',
  'kn',
  'kp',
  'kr',
  'kw',
  'kz',
  'la',
  'lb',
  'lc',
  'li',
  'lk',
  'lr',
  'ls',
  'lt',
  'lu',
  'lv',
  'ly',
  'ma',
  'mc',
  'md',
  'mf',
  'mg',
  'mh',
  'mk',
  'ml',
  'mm',
  'mn',
  'mo',
  'mq',
  'mr',
  'ms',
  'mt',
  'mu',
  'mv',
  'mw',
  'my',
  'mz',
  'na',
  'nc',
  'ne',
  'nf',
  'ng',
  'ni',
  'nl',
  'no',
  'np',
  'nr',
  'nu',
  'nz',
  'pa',
  'pe',
  'pf',
  'pg',
  'ph',
  'pk',
  'pl',
  'pm',
  'pn',
  'pr',
  'ps',
  'pt',
  'pw',
  'py',
  'qa',
  're',
  'ro',
  'ru',
  'rw',
  'sa',
  'sb',
  'sc',
  'sd',
  'se',
  'sg',
  'sh',
  'si',
  'sj',
  'sk',
  'sl',
  'sm',
  'sn',
  'so',
  'sr',
  'ss',
  'st',
  'sx',
  'sy',
  'sz',
  'tc',
  'td',
  'tf',
  'tg',
  'th',
  'tj',
  'tk',
  'tl',
  'tn',
  'to',
  'tr',
  'tt',
  'tv',
  'tw',
  'tz',
  'ua',
  'ug',
  'um',
  'us',
  'uy',
  'uz',
  'vc',
  've',
  'vg',
  'vi',
  'vn',
  'vu',
  'wf',
  'ws',
  'xk',
  'ye',
  'yt',
  'za',
  'zm',
  'zw',
};

final _bracketCode = RegExp(r'^[\[(]\s*([A-Za-z]{2})\s*[\])]');
final _threeLetterCode =
    RegExp(r'^(USA|UAE)(?=\s|[-–—|:·•_/\\]|$)', caseSensitive: false);
final _plainCode = RegExp(r'^([A-Za-z]{2})(?=\s|[-–—|:·•_/\\]|$)');
final _leadingSeparator = RegExp(r'^\s*(?:[-–—|:·•_/\\]+\s*)?');

/// Parses a leading `DE`, `[DE]`, `🇩🇪`, or a pair such as `🇩🇪 DE`.
///
/// Returns null when the name does not start with a country the app can draw.
/// A code must be followed by a boundary, so `DEDoVPN` is a name, not Germany.
CountryTag? countryTagFrom(String raw) {
  final original = raw.trim();
  if (original.isEmpty) return null;

  var rest = original;
  String? code;
  var tookCode = false;
  // Two passes are enough for the shapes providers actually use: emoji + code
  // or code + emoji. A second code is not taken — `DE No DoDoVPN` must not
  // lose `No` to Norway.
  for (var pass = 0; pass < 2; pass++) {
    rest = rest.trimLeft();
    final emoji = _takeLeadingFlagEmoji(rest);
    if (emoji != null) {
      code ??= emoji.$1;
      rest = emoji.$2;
      continue;
    }
    if (tookCode) break;
    final text = _takeLeadingCode(rest);
    if (text != null) {
      code ??= text.$1;
      tookCode = true;
      rest = text.$2;
      continue;
    }
    break;
  }

  if (code == null) return null;
  final title = rest.replaceFirst(_leadingSeparator, '').trim();
  return CountryTag(code: code, title: title.isEmpty ? original : title);
}

/// Normalizes a country code or the aliases providers commonly use.
String? normalizeCountryCode(String value) {
  final code = value.trim().toLowerCase();
  if (code.length == 2 && kCountryFlagCodes.contains(code)) return code;
  return switch (code) {
    'uk' => 'gb',
    'usa' => 'us',
    'uae' => 'ae',
    _ => null,
  };
}

/// `de` → `🇩🇪`. Null when the app has no flag for the code.
String? flagEmojiForCountryCode(String value) {
  final code = normalizeCountryCode(value);
  if (code == null) return null;
  final upper = code.toUpperCase();
  const base = 0x1F1E6;
  return String.fromCharCodes([
    base + upper.codeUnitAt(0) - 0x41,
    base + upper.codeUnitAt(1) - 0x41,
  ]);
}

/// `🇩🇪` → `de`. Null when [value] is not exactly one country flag.
String? countryCodeFromFlagEmoji(String value) {
  final runes = value.runes.toList();
  if (runes.length < 2) return null;
  final code = _regionalCode(runes[0], runes[1]);
  if (code == null) return null;
  final tail = runes.length - (runes.length == 3 && runes[2] == 0xFE0F ? 3 : 2);
  if (tail != 0) return null;
  return normalizeCountryCode(code);
}

/// A flag value as the app stores it: an ISO code or its emoji.
String? countryCodeForFlagValue(String value) =>
    normalizeCountryCode(value) ?? countryCodeFromFlagEmoji(value.trim());

(String, String)? _takeLeadingCode(String raw) {
  final bracket = _bracketCode.firstMatch(raw);
  if (bracket != null) {
    final code = normalizeCountryCode(bracket.group(1)!);
    final rest = raw.substring(bracket.end);
    if (code != null && _tagShapeAllows(bracket.group(1)!, rest)) {
      return (code, rest);
    }
  }
  final alias = _threeLetterCode.firstMatch(raw);
  if (alias != null) {
    final code = normalizeCountryCode(alias.group(1)!);
    final rest = raw.substring(alias.end);
    if (code != null && _tagShapeAllows(alias.group(1)!, rest)) {
      return (code, rest);
    }
  }
  final plain = _plainCode.firstMatch(raw);
  if (plain != null) {
    final code = normalizeCountryCode(plain.group(1)!);
    final rest = raw.substring(plain.end);
    if (code != null && _tagShapeAllows(plain.group(1)!, rest)) {
      return (code, rest);
    }
  }
  return null;
}

/// A two-letter word is not automatically a country.
///
/// `No lag` and `In stock` are names that happen to start with ISO codes. A
/// provider's tag is either uppercase (`DE`, `NL`) or lowercase followed by a
/// proper name (`de DoDoVPN`); `No` and `In` are neither.
bool _tagShapeAllows(String rawCode, String rest) {
  if (rawCode != rawCode.toUpperCase() && rawCode != rawCode.toLowerCase()) {
    return false;
  }
  if (rawCode == rawCode.toUpperCase()) return true;
  final name = rest.replaceFirst(_leadingSeparator, '').trimLeft();
  if (name.isEmpty) return true;
  final first = name.runes.first;
  return (first >= 0x30 && first <= 0x39) || (first >= 0x41 && first <= 0x5A);
}

(String, String)? _takeLeadingFlagEmoji(String raw) {
  final runes = raw.runes.toList();
  if (runes.length < 2) return null;
  final regional = _regionalCode(runes[0], runes[1]);
  if (regional == null) return null;
  final code = normalizeCountryCode(regional);
  if (code == null) return null;
  final end = runes.length > 2 && runes[2] == 0xFE0F ? 3 : 2;
  return (code, String.fromCharCodes(runes.sublist(end)));
}

/// Two regional indicators to an uppercase two-letter code.
String? _regionalCode(int first, int second) {
  const base = 0x1F1E6;
  if (first < base || first > base + 25) return null;
  if (second < base || second > base + 25) return null;
  return String.fromCharCodes([
    first - base + 0x41,
    second - base + 0x41,
  ]);
}
