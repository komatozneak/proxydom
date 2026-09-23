import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'hy2_link_parser.dart';
import 'share_link_parser.dart';

const _prefsKey = 'hy2_import_v1';

/// Local paste list. Not an account and not a Teremok entitlement.
class Hy2ImportStore {
  Hy2ImportStore._();
  static final Hy2ImportStore instance = Hy2ImportStore._();

  Future<List<ParsedShareLink>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    final lines = decoded['lines'];
    if (lines is! List) return const [];
    final out = <ParsedShareLink>[];
    for (final item in lines) {
      if (item is! String) continue;
      try {
        out.add(parseShareLink(item));
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

  Future<String?> sourceHost() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final source = decoded['source'];
    if (source is! String || source.trim().isEmpty) return null;
    return source.trim();
  }

  Future<ParsedShareLink?> selected() async {
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
  Future<void> removeAt(int index) async {
    final links = await load();
    if (index < 0 || index >= links.length) return;
    final lines = links.map((link) => link.raw).toList()..removeAt(index);
    var selected = await selectedIndex();
    if (lines.isEmpty) {
      selected = 0;
    } else if (selected >= lines.length) {
      selected = lines.length - 1;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({'lines': lines, 'selected': selected}),
    );
  }

  Future<List<ParsedShareLink>> saveInput(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('empty');
    }
    final body = looksLikeSubscriptionUrl(text) ? await _fetch(text) : text;
    final links = parseShareSubscription(body);
    if (links.isEmpty) {
      throw const FormatException('no links');
    }
    final lines = links.map((link) => link.raw).toList();
    final source = looksLikeSubscriptionUrl(text)
        ? Uri.tryParse(text)?.host
        : null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'lines': lines,
        'selected': 0,
        if (source != null && source.isNotEmpty) 'source': source,
      }),
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
