import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'hy2_link_parser.dart';

const _prefsKey = 'hy2_import_v1';

/// Local paste list. Not an account and not a Teremok entitlement.
class Hy2ImportStore {
  Hy2ImportStore._();
  static final Hy2ImportStore instance = Hy2ImportStore._();

  Future<List<ParsedHy2Link>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    final lines = decoded['lines'];
    if (lines is! List) return const [];
    final out = <ParsedHy2Link>[];
    for (final item in lines) {
      if (item is! String) continue;
      try {
        out.add(parseHy2Link(item));
      } on FormatException {
        continue;
      }
    }
    return out;
  }

  Future<int> selectedIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return 0;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return 0;
    final index = decoded['selected'];
    return index is int ? index : 0;
  }

  Future<ParsedHy2Link?> selected() async {
    final links = await load();
    if (links.isEmpty) return null;
    var index = await selectedIndex();
    if (index < 0 || index >= links.length) index = 0;
    return links[index];
  }

  Future<void> select(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final decoded = raw == null || raw.isEmpty
        ? <String, Object>{'lines': <String>[], 'selected': index}
        : Map<String, Object?>.from(jsonDecode(raw) as Map);
    decoded['selected'] = index;
    await prefs.setString(_prefsKey, jsonEncode(decoded));
  }

  /// Accept one URI, a subscription body, or an http(s) URL that returns one.
  Future<List<ParsedHy2Link>> saveInput(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('empty');
    }
    final body = looksLikeSubscriptionUrl(text) ? await _fetch(text) : text;
    final links = parseHy2Subscription(body);
    if (links.isEmpty) {
      throw const FormatException('no hysteria2 links');
    }
    final lines = <String>[];
    if (looksLikeSubscriptionUrl(text)) {
      for (final line in body.split(RegExp(r'\r?\n'))) {
        final item = line.trim();
        if (item.startsWith('hysteria2://') || item.startsWith('hy2://')) {
          lines.add(item);
        }
      }
    } else if (text.startsWith('hysteria2://') || text.startsWith('hy2://')) {
      lines.add(text);
    } else {
      for (final line in text.split(RegExp(r'\r?\n'))) {
        final item = line.trim();
        if (item.startsWith('hysteria2://') || item.startsWith('hy2://')) {
          lines.add(item);
        }
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({'lines': lines, 'selected': 0}),
    );
    return links;
  }

  Future<String> _fetch(String url) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw FormatException('http ${response.statusCode}');
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }
}
