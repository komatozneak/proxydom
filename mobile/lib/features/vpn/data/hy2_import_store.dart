import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'hy2_link_parser.dart';
import 'share_link_parser.dart';
import 'subscription_label.dart';

const _prefsKey = 'hy2_import_v1';

/// Local paste list. Not an account and not a Teremok entitlement.
class Hy2ImportStore {
  Hy2ImportStore._();
  static final Hy2ImportStore instance = Hy2ImportStore._();

  final _changes = StreamController<void>.broadcast(sync: true);

  /// Fires after a profile list write. Screens reload from this, not from init.
  Stream<void> get changes => _changes.stream;

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

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

  Future<String?> sourceUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final url = decoded['url'];
    if (url is! String || url.trim().isEmpty) return null;
    return url.trim();
  }

  /// Re-fetch the saved https subscription. A dead slot (404) drops the profile.
  Future<void> refreshSavedUrl() async {
    final url = await sourceUrl();
    if (url == null) return;
    try {
      await saveInput(url);
    } on FormatException catch (e) {
      if (e.message.contains('404')) {
        await clear();
        return;
      }
      rethrow;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    _changed();
  }

  Future<String?> profileTitle() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final title = decoded['title'];
    if (title is! String || title.trim().isEmpty) return null;
    return title.trim();
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
    _changed();
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
    final source = await sourceHost();
    final title = await profileTitle();
    final url = await sourceUrl();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'lines': lines,
        'selected': selected,
        if (source != null && source.isNotEmpty) 'source': source,
        if (url != null) 'url': url,
        if (title != null && lines.isNotEmpty) 'title': title,
      }),
    );
    _changed();
  }

  Future<List<ParsedShareLink>> saveInput(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('empty');
    }
    final fetched = looksLikeSubscriptionUrl(text)
        ? await _fetch(text)
        : (body: text, profileTitle: null);
    final body = fetched.body;
    final links = parseShareSubscription(body);
    if (links.isEmpty) {
      throw const FormatException('no links');
    }
    final lines = links.map((link) => link.raw).toList();
    final source = looksLikeSubscriptionUrl(text)
        ? Uri.tryParse(text)?.host
        : null;
    final title = fetched.profileTitle ?? titleFromSubscriptionBody(body);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'lines': lines,
        'selected': 0,
        if (source != null && source.isNotEmpty) 'source': source,
        if (looksLikeSubscriptionUrl(text)) 'url': text,
        if (title != null && title.isNotEmpty) 'title': title,
      }),
    );
    _changed();
    return links;
  }

  /// Download a subscription and parse it without writing the store.
  Future<({List<ParsedShareLink> links, String? title})> previewSubscription(
    String url,
  ) async {
    final fetched = await _fetch(url);
    final links = parseShareSubscription(fetched.body);
    if (links.isEmpty) {
      throw const FormatException('no links');
    }
    final title =
        fetched.profileTitle ?? titleFromSubscriptionBody(fetched.body);
    return (links: links, title: title);
  }

  Future<({String body, String? profileTitle})> _fetch(String url) async {
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
      final header = response.headers.value('profile-title');
      return (body: body, profileTitle: decodeProfileTitle(header));
    } finally {
      client.close(force: true);
    }
  }
}
