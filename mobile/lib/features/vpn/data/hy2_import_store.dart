import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'document_fetch_log.dart';
import 'hy2_link_parser.dart';
import 'route_document.dart';
import 'share_link_parser.dart';
import 'subscription_device.dart';
import 'subscription_label.dart';
import 'subscription_notice.dart';
import 'subscription_traffic.dart';
import '../../../core/ios_store_gates.dart';

const _prefsKey = 'hy2_import_v1';

/// One subscription or one manual paste. Not mixed with another source.
class ShareCatalog {
  const ShareCatalog({
    required this.id,
    required this.title,
    required this.lines,
    this.url,
    this.etag,
    this.fallbackTitle,
    this.titleIsCustom = false,
    this.trafficMeta,
    this.updateIntervalHours,
    this.lastUpdated,
    this.webPageUrl,
    this.supportUrl,
    this.announce,
    this.announceFrame = false,
  });

  final String id;
  final String title;
  final List<String> lines;
  final String? url;

  /// Last `ETag` from this document. Sent as `If-None-Match`.
  final String? etag;

  /// Name from the URL `#fragment` when the server sends no `Profile-Title`.
  final String? fallbackTitle;

  /// True after a person renames the list. Refresh must not overwrite it.
  final bool titleIsCustom;

  /// Last `subscription-userinfo` snapshot from this document.
  ///
  /// A display hint for the whole document, not an account balance.
  /// A failed refresh keeps it. The document drop is what clears it.
  final String? trafficMeta;
  final int? updateIntervalHours;
  final String? lastUpdated;
  final String? webPageUrl;
  final String? supportUrl;
  final String? announce;

  /// Rounded border around [announce]. A saved list from before this field
  /// still frames the text: that is how Happ draws every announcement.
  final bool announceFrame;

  /// What Share copies: the document address, or the pasted lines.
  String? get subscriptionKey {
    final document = url?.trim();
    if (document != null && document.isNotEmpty) return document;
    final kept = [
      for (final line in lines)
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (kept.isEmpty) return null;
    return kept.join('\n');
  }

  ShareCatalog copyWith({
    String? title,
    List<String>? lines,
    Object? url = _keep,
    Object? etag = _keep,
    Object? fallbackTitle = _keep,
    bool? titleIsCustom,
    Object? trafficMeta = _keep,
    Object? updateIntervalHours = _keep,
    Object? lastUpdated = _keep,
    Object? webPageUrl = _keep,
    Object? supportUrl = _keep,
    Object? announce = _keep,
    Object? announceFrame = _keep,
  }) {
    return ShareCatalog(
      id: id,
      title: title ?? this.title,
      lines: lines ?? this.lines,
      url: identical(url, _keep) ? this.url : url as String?,
      etag: identical(etag, _keep) ? this.etag : etag as String?,
      fallbackTitle: identical(fallbackTitle, _keep)
          ? this.fallbackTitle
          : fallbackTitle as String?,
      titleIsCustom: titleIsCustom ?? this.titleIsCustom,
      trafficMeta: identical(trafficMeta, _keep)
          ? this.trafficMeta
          : trafficMeta as String?,
      updateIntervalHours: identical(updateIntervalHours, _keep)
          ? this.updateIntervalHours
          : updateIntervalHours as int?,
      lastUpdated: identical(lastUpdated, _keep)
          ? this.lastUpdated
          : lastUpdated as String?,
      webPageUrl: identical(webPageUrl, _keep)
          ? this.webPageUrl
          : webPageUrl as String?,
      supportUrl: identical(supportUrl, _keep)
          ? this.supportUrl
          : supportUrl as String?,
      announce:
          identical(announce, _keep) ? this.announce : announce as String?,
      announceFrame: identical(announceFrame, _keep)
          ? this.announceFrame
          : announceFrame as bool,
    );
  }
}

/// What a manual refresh did to one list.
enum ShareRefreshKind { updated, unchanged, deleted }

class ShareRefreshOutcome {
  const ShareRefreshOutcome({
    required this.kind,
    this.count = 0,
    this.selectionLeftThisList = false,
  });

  final ShareRefreshKind kind;
  final int count;

  /// The chosen server was in this list and is no longer there.
  final bool selectionLeftThisList;
}

const _keep = Object();

/// Local catalogs. Not an account and not an entitlement.
class Hy2ImportStore {
  Hy2ImportStore._();
  static final Hy2ImportStore instance = Hy2ImportStore._();

  final _changes = StreamController<void>.broadcast(sync: true);

  /// Fires after a profile list write. Screens reload from this, not from init.
  Stream<void> get changes => _changes.stream;

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Seeds the store from a test. The capture harness needs a profile document
  /// to draw; on a device there is none, and the store is private on purpose —
  /// nothing in the app writes catalogs directly, only documents do.
  @visibleForTesting
  Future<void> seedForTest(List<ShareCatalog> catalogs) async {
    final blob = await _read();
    await _write(blob.copyWith(catalogs: catalogs));
  }

  Future<List<ShareCatalog>> catalogs() async {
    return (await _read()).catalogs;
  }

  Future<List<ParsedShareLink>> load() async {
    return _parseAll(await _read());
  }

  Future<int> selectedIndex() async {
    return (await _read()).selected;
  }

  /// Re-fetch every saved subscription. A dead slot (404) drops that catalog.
  Future<void> refreshSavedUrl() async {
    final blob = await _read();
    final key = _keyAt(blob, blob.selected);
    var catalogs = List<ShareCatalog>.from(blob.catalogs);
    var changed = false;
    for (final catalog in List<ShareCatalog>.from(catalogs)) {
      final url = catalog.url;
      if (url == null || url.isEmpty) continue;
      try {
        final pulled = await _pull(catalog);
        if (pulled == null) {
          catalogs = _replaceCatalog(
            catalogs,
            catalog.id,
            _Pulled(
              title: catalog.title,
              lines: catalog.lines,
              etag: catalog.etag,
              lastUpdated: DateTime.now().toUtc().toIso8601String(),
              trafficMeta: catalog.trafficMeta,
              updateIntervalHours: catalog.updateIntervalHours,
              webPageUrl: catalog.webPageUrl,
              supportUrl: catalog.supportUrl,
              announce: catalog.announce,
              announceFrame: catalog.announceFrame,
              url: catalog.url,
            ),
          );
          changed = true;
          continue;
        }
        catalogs = _replaceCatalog(catalogs, catalog.id, pulled);
        changed = true;
      } on SubscriptionDocumentException {
        continue;
      } on DocumentSyncException catch (e) {
        if (e.decision != DocumentSyncDecision.drop) continue;
        catalogs = [
          for (final item in catalogs)
            if (item.id != catalog.id) item,
        ];
        changed = true;
      } on SocketException {
        continue;
      } on TimeoutException {
        continue;
      }
    }
    if (!changed) return;
    await _write(
      blob.copyWith(
        catalogs: catalogs,
        selected: _indexOfKey(catalogs, key),
      ),
    );
  }

  /// One list, from its saved URL.
  ///
  /// `304` leaves the list. `404` drops only this list. A network error or
  /// `5xx` throws and leaves the saved lines in place.
  Future<ShareRefreshOutcome> refreshCatalog(String id) async {
    final blob = await _read();
    ShareCatalog? catalog;
    for (final item in blob.catalogs) {
      if (item.id == id) catalog = item;
    }
    final url = catalog?.url;
    if (catalog == null || url == null || url.isEmpty) {
      throw const FormatException('no url');
    }
    final key = _keyAt(blob, blob.selected);
    final owned = _catalogOwnsKey(catalog, key);
    try {
      final pulled = await _pull(catalog);
      if (pulled == null) {
        final stamped = catalog.copyWith(
          lastUpdated: DateTime.now().toUtc().toIso8601String(),
        );
        final catalogs = _replaceCatalog(
          blob.catalogs,
          id,
          _Pulled.fromCatalog(stamped),
        );
        await _write(blob.copyWith(catalogs: catalogs));
        return ShareRefreshOutcome(
          kind: ShareRefreshKind.unchanged,
          count: catalog.lines.length,
        );
      }
      final catalogs = _replaceCatalog(blob.catalogs, id, pulled);
      final stillThere = key != null &&
          pulled.lines.any((line) => shareServerKey(line) == key);
      await _write(
        blob.copyWith(
          catalogs: catalogs,
          selected: shareRefreshIndex(
            catalogs: catalogs,
            catalogId: id,
            key: stillThere ? key : null,
            owned: owned && !stillThere,
          ),
        ),
      );
      return ShareRefreshOutcome(
        kind: ShareRefreshKind.updated,
        count: pulled.lines.length,
        selectionLeftThisList: owned && !stillThere,
      );
    } on DocumentSyncException catch (e) {
      if (e.decision != DocumentSyncDecision.drop) {
        return ShareRefreshOutcome(
          kind: ShareRefreshKind.unchanged,
          count: catalog.lines.length,
        );
      }
      final catalogs = [
        for (final item in blob.catalogs)
          if (item.id != id) item,
      ];
      await _write(
        blob.copyWith(
          catalogs: catalogs,
          selected: _indexOfKey(catalogs, owned ? null : key),
        ),
      );
      return ShareRefreshOutcome(
        kind: ShareRefreshKind.deleted,
        selectionLeftThisList: owned,
      );
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    _changed();
  }

  Future<String?> profileTitle() async {
    final blob = await _read();
    final catalog = _catalogAt(blob, blob.selected);
    final title = catalog?.title.trim() ?? '';
    return title.isEmpty ? null : title;
  }

  /// Catalog that owns the selected line.
  Future<ShareCatalog?> selectedCatalog() async {
    final blob = await _read();
    if (blob.catalogs.isEmpty) return null;
    return _catalogAt(blob, blob.selected);
  }

  /// `subscription-userinfo` of the catalog that owns the selected line.
  Future<String?> selectedTrafficMeta() async {
    final blob = await _read();
    if (blob.catalogs.isEmpty) return null;
    return _catalogAt(blob, blob.selected)?.trafficMeta;
  }

  Future<ParsedShareLink?> selected() async {
    final links = await load();
    if (links.isEmpty) return null;
    var index = await selectedIndex();
    if (index < 0 || index >= links.length) index = 0;
    return links[index];
  }

  Future<void> select(int index) async {
    final blob = await _read();
    await _write(blob.copyWith(selected: index));
  }

  Future<void> removeCatalog(String id) async {
    final blob = await _read();
    var flat = 0;
    var start = -1;
    var length = 0;
    for (final catalog in blob.catalogs) {
      if (catalog.id == id) {
        start = flat;
        length = catalog.lines.length;
        break;
      }
      flat += catalog.lines.length;
    }
    if (start < 0) return;
    final catalogs = [
      for (final catalog in blob.catalogs)
        if (catalog.id != id) catalog,
    ];
    await _write(
      blob.copyWith(
        catalogs: catalogs,
        selected: _selectedAfterRemoval(
          blob.selected,
          start,
          length,
          _lineCount(catalogs),
        ),
      ),
    );
  }

  /// Accept one URI, a subscription body, or an http(s) URL that returns one.
  Future<void> removeAt(int index) async {
    final blob = await _read();
    var cursor = 0;
    ShareCatalog? hit;
    var local = 0;
    for (final catalog in blob.catalogs) {
      if (index < cursor + catalog.lines.length) {
        hit = catalog;
        local = index - cursor;
        break;
      }
      cursor += catalog.lines.length;
    }
    if (hit == null) return;
    final lines = List<String>.from(hit.lines)..removeAt(local);
    final catalogs = [
      for (final catalog in blob.catalogs)
        if (catalog.id != hit.id)
          catalog
        else if (lines.isNotEmpty)
          catalog.copyWith(lines: lines),
    ];
    await _write(
      blob.copyWith(
        catalogs: catalogs,
        selected: _selectedAfterRemoval(
          blob.selected,
          index,
          1,
          _lineCount(catalogs),
        ),
      ),
    );
  }

  Future<List<ParsedShareLink>> saveInput(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('empty');
    }
    final target = subscriptionDocumentTarget(text);
    final String body;
    final String? profileTitle;
    final String? etag;
    final String? trafficMeta;
    final String? hwidMaxDevices;
    final SubscriptionNotice notice;
    if (target == null) {
      body = text;
      profileTitle = null;
      etag = null;
      trafficMeta = subscriptionTrafficMeta(body: text);
      hwidMaxDevices = null;
      notice = subscriptionNotice(body: text);
    } else {
      final fetched = await _fetch(target.url);
      body = fetched.body;
      profileTitle = fetched.profileTitle;
      etag = fetched.etag;
      hwidMaxDevices = fetched.hwidMaxDevices;
      trafficMeta = subscriptionTrafficMeta(
        header: fetched.userInfo,
        body: fetched.body,
      );
      notice = fetched.notice;
    }
    final links = _linesToKeep(
      parseShareSubscription(body),
      hwidMaxDevices: hwidMaxDevices,
    );
    if (links.isEmpty) {
      throw const FormatException('no links');
    }
    final incoming = links.map((link) => link.raw).toList();
    final title = _titleFor(
      profileTitle ?? target?.title ?? titleFromSubscriptionBody(body),
      links,
    );
    final blob = await _read();
    final catalogs = List<ShareCatalog>.from(blob.catalogs);
    var selected = 0;
    if (target != null) {
      final existing =
          catalogs.indexWhere((catalog) => catalog.url == target.url);
      if (existing >= 0) {
        final previous = catalogs[existing];
        catalogs[existing] = previous.copyWith(
          title: previous.titleIsCustom ? previous.title : title,
          lines: incoming,
          etag: etag,
          fallbackTitle: target.title,
          trafficMeta: keptTrafficMeta(
            observed: trafficMeta,
            saved: previous.trafficMeta,
          ),
          lastUpdated: DateTime.now().toUtc().toIso8601String(),
          supportUrl: notice.planeUrl,
          announce: notice.text,
          announceFrame: notice.frame,
        );
      } else {
        catalogs.add(
          ShareCatalog(
            id: _newId(),
            title: title,
            lines: incoming,
            url: target.url,
            etag: etag,
            fallbackTitle: target.title,
            trafficMeta: keptTrafficMeta(observed: trafficMeta),
            lastUpdated: DateTime.now().toUtc().toIso8601String(),
            supportUrl: notice.planeUrl,
            announce: notice.text,
            announceFrame: notice.frame,
          ),
        );
      }
      var cursor = 0;
      for (final catalog in catalogs) {
        if (catalog.url == target.url) {
          selected = cursor;
          break;
        }
        cursor += catalog.lines.length;
      }
    } else {
      selected = _lineCount(catalogs);
      catalogs.add(
        ShareCatalog(
          id: _newId(),
          title: title,
          lines: incoming,
          trafficMeta: trafficMeta,
          supportUrl: notice.planeUrl,
          announce: notice.text,
          announceFrame: notice.frame,
        ),
      );
    }
    final next = blob.copyWith(catalogs: catalogs, selected: selected);
    await _write(next);
    return _parseAll(next);
  }

  /// Download a subscription and parse it without writing the store.
  Future<({List<ParsedShareLink> links, String? title})> previewSubscription(
    String raw,
  ) async {
    final target = subscriptionDocumentTarget(raw);
    if (target == null) throw const FormatException('subscription');
    final fetched = await _fetch(target.url);
    final links = _linesToKeep(
      parseShareSubscription(fetched.body),
      hwidMaxDevices: fetched.hwidMaxDevices,
    );
    if (links.isEmpty) {
      logDocumentFetch(
        url: target.url,
        links: 0,
        decision: 'drop',
        error: 'no_links',
      );
      throw const FormatException('no links');
    }
    logDocumentFetch(
      url: target.url,
      links: links.length,
      decision: 'replace',
    );
    final title = fetched.profileTitle ??
        target.title ??
        titleFromSubscriptionBody(fetched.body);
    return (links: links, title: title);
  }

  Future<_Fetched> _fetch(
    String url, {
    String? etag,
    int? localLinks,
  }) async {
    final started = Stopwatch()..start();
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.userAgentHeader, 'ProxyDom/1.0');
      final deviceHeaders = await subscriptionHeaderSource();
      for (final entry in deviceHeaders.entries) {
        if (entry.key.toLowerCase() == 'user-agent') continue;
        request.headers.set(entry.key, entry.value);
      }
      if (etag != null && etag.isNotEmpty) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode == HttpStatus.notModified) {
        await response.drain<void>();
        logDocumentFetch(
          url: url,
          elapsedMs: started.elapsedMilliseconds,
          status: response.statusCode,
          decision: 'keep',
          localLinks: localLinks,
        );
        return _Fetched(
          body: '',
          etag: etag,
          status: response.statusCode,
        );
      }
      final body = await response.transform(utf8.decoder).join();
      final decision = decideDocumentSync(
        status: response.statusCode,
        body: body,
      );
      if (decision == DocumentSyncDecision.drop ||
          decision == DocumentSyncDecision.keep) {
        logDocumentFetch(
          url: url,
          elapsedMs: started.elapsedMilliseconds,
          status: response.statusCode,
          decision: decision.name,
          error: decision.name,
        );
        throw DocumentSyncException(decision);
      }
      logDocumentFetch(
        url: url,
        elapsedMs: started.elapsedMilliseconds,
        status: response.statusCode,
        decision: 'fetched',
      );
      final redirect = response.headers.value('new-url') ??
          response.headers.value('fallback-url');
      final notice = subscriptionNotice(
        announceHeader: response.headers.value('announce'),
        supportHeader: response.headers.value('support-url'),
        frameHeader: response.headers.value('announce-frame'),
        body: body,
      );
      return _Fetched(
        body: body,
        profileTitle:
            decodeProfileTitle(response.headers.value('profile-title')),
        etag: response.headers.value('etag'),
        status: response.statusCode,
        userInfo: response.headers.value('subscription-userinfo'),
        hwidMaxDevices: response.headers.value('x-hwid-max-devices-reached'),
        updateIntervalHours: parseUpdateIntervalHours(
          response.headers.value('profile-update-interval'),
        ),
        webPageUrl: response.headers.value('profile-web-page-url'),
        supportUrl: notice.planeUrl,
        announce: notice.text,
        announceFrame: notice.frame,
        notice: notice,
        redirectUrl: redirect,
      );
    } on SocketException catch (e) {
      logDocumentFetch(
        url: url,
        elapsedMs: started.elapsedMilliseconds,
        decision: 'keep',
        error: 'SocketException',
        detail: e,
      );
      throw const DocumentSyncException(DocumentSyncDecision.keep);
    } on TimeoutException catch (e) {
      logDocumentFetch(
        url: url,
        elapsedMs: started.elapsedMilliseconds,
        decision: 'keep',
        error: 'TimeoutException',
        detail: e,
      );
      throw const DocumentSyncException(DocumentSyncDecision.keep);
    } finally {
      client.close(force: true);
    }
  }

  Future<File> _windowsDocumentsFile() async {
    final root = Platform.environment['LOCALAPPDATA'];
    final dir = Directory('${root ?? '.'}${Platform.pathSeparator}ProxyDom${Platform.pathSeparator}storage');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}documents.json');
  }

  Future<_Blob> _read() async {
    if (windowsDesktop) {
      final file = await _windowsDocumentsFile();
      if (!await file.exists()) return const _Blob();
      final raw = await file.readAsString();
      if (raw.isEmpty) return const _Blob();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const _Blob();
      return _Blob.fromJson(decoded);
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const _Blob();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const _Blob();
    return _Blob.fromJson(decoded);
  }

  Future<void> _write(_Blob blob) async {
    final catalogs = [
      for (final catalog in blob.catalogs)
        if (catalog.lines.isNotEmpty) catalog,
    ];
    final encoded = catalogs.isEmpty
        ? null
        : jsonEncode(blob.copyWith(catalogs: catalogs).toJson());
    if (windowsDesktop) {
      final file = await _windowsDocumentsFile();
      if (encoded == null) {
        if (await file.exists()) await file.delete();
      } else {
        await file.writeAsString(encoded);
      }
      _changed();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (encoded == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, encoded);
    }
    _changed();
  }

  List<ParsedShareLink> _parseAll(_Blob blob) {
    final out = <ParsedShareLink>[];
    for (final catalog in blob.catalogs) {
      for (final item in catalog.lines) {
        try {
          out.add(parseShareLink(item));
        } on FormatException {
          continue;
        }
      }
    }
    return out;
  }
}

class _Fetched {
  const _Fetched({
    required this.body,
    required this.status,
    this.profileTitle,
    this.etag,
    this.userInfo,
    this.hwidMaxDevices,
    this.updateIntervalHours,
    this.webPageUrl,
    this.supportUrl,
    this.announce,
    this.announceFrame = false,
    this.notice = const SubscriptionNotice(),
    this.redirectUrl,
  });

  final String body;
  final int status;
  final String? profileTitle;
  final String? etag;
  final String? userInfo;
  final String? hwidMaxDevices;
  final int? updateIntervalHours;
  final String? webPageUrl;
  final String? supportUrl;
  final String? announce;
  final bool announceFrame;
  final SubscriptionNotice notice;
  final String? redirectUrl;
}

class _Pulled {
  const _Pulled({
    required this.title,
    required this.lines,
    this.etag,
    this.url,
    this.trafficMeta,
    this.updateIntervalHours,
    this.lastUpdated,
    this.webPageUrl,
    this.supportUrl,
    this.announce,
    this.announceFrame = false,
  });

  factory _Pulled.fromCatalog(ShareCatalog catalog) {
    return _Pulled(
      title: catalog.title,
      lines: catalog.lines,
      etag: catalog.etag,
      url: catalog.url,
      trafficMeta: catalog.trafficMeta,
      updateIntervalHours: catalog.updateIntervalHours,
      lastUpdated: catalog.lastUpdated,
      webPageUrl: catalog.webPageUrl,
      supportUrl: catalog.supportUrl,
      announce: catalog.announce,
      announceFrame: catalog.announceFrame,
    );
  }

  final String title;
  final List<String> lines;
  final String? etag;
  final String? url;
  final String? trafficMeta;
  final int? updateIntervalHours;
  final String? lastUpdated;
  final String? webPageUrl;
  final String? supportUrl;
  final String? announce;
  final bool announceFrame;
}

Future<_Pulled?> _pull(ShareCatalog catalog, {bool followed = false}) async {
  final url = catalog.url;
  if (url == null || url.isEmpty) return null;
  final fetched = await Hy2ImportStore.instance._fetch(
    url,
    etag: etagUnlessTrafficUnknown(
      etag: catalog.etag,
      trafficKnown: hasTrafficSnapshot(catalog.trafficMeta),
    ),
    localLinks: catalog.lines.length,
  );
  if (fetched.status == HttpStatus.notModified) return null;
  final nextUrl = fetched.redirectUrl?.trim();
  if (!followed && nextUrl != null && nextUrl.isNotEmpty && nextUrl != url) {
    return _pull(catalog.copyWith(url: nextUrl), followed: true);
  }
  final links = _linesToKeep(
    parseShareSubscription(fetched.body),
    hwidMaxDevices: fetched.hwidMaxDevices,
  );
  if (links.isEmpty) {
    logDocumentFetch(
      url: url,
      status: fetched.status,
      links: 0,
      decision: 'drop',
      error: 'no_links',
    );
    throw const DocumentSyncException(DocumentSyncDecision.drop);
  }
  logDocumentFetch(
    url: url,
    status: fetched.status,
    links: links.length,
    decision: 'replace',
  );
  final title = catalog.titleIsCustom
      ? catalog.title
      : _titleFor(
          fetched.profileTitle ??
              catalog.fallbackTitle ??
              titleFromSubscriptionBody(fetched.body),
          links,
        );
  return _Pulled(
    title: title,
    lines: [for (final link in links) link.raw],
    etag: fetched.etag,
    url: catalog.url,
    trafficMeta: keptTrafficMeta(
      observed: subscriptionTrafficMeta(
        header: fetched.userInfo,
        body: fetched.body,
      ),
      saved: catalog.trafficMeta,
    ),
    updateIntervalHours: fetched.updateIntervalHours,
    lastUpdated: DateTime.now().toUtc().toIso8601String(),
    webPageUrl: fetched.webPageUrl,
    supportUrl: fetched.supportUrl,
    announce: fetched.announce,
    announceFrame: fetched.announceFrame,
  );
}

List<ShareCatalog> _replaceCatalog(
  List<ShareCatalog> catalogs,
  String id,
  _Pulled pulled,
) {
  return [
    for (final item in catalogs)
      if (item.id == id)
        item.copyWith(
          title: pulled.title,
          lines: pulled.lines,
          etag: pulled.etag,
          url: pulled.url ?? item.url,
          trafficMeta: pulled.trafficMeta,
          updateIntervalHours: pulled.updateIntervalHours,
          lastUpdated: pulled.lastUpdated,
          webPageUrl: pulled.webPageUrl,
          supportUrl: pulled.supportUrl,
          announce: pulled.announce,
          announceFrame: pulled.announceFrame,
        )
      else
        item,
  ];
}

String? _keyAt(_Blob blob, int index) {
  var cursor = 0;
  for (final catalog in blob.catalogs) {
    for (final line in catalog.lines) {
      if (cursor == index) return shareServerKey(line);
      cursor++;
    }
  }
  return null;
}

int _indexOfKey(List<ShareCatalog> catalogs, String? key) {
  if (key == null) return 0;
  var cursor = 0;
  for (final catalog in catalogs) {
    for (final line in catalog.lines) {
      if (shareServerKey(line) == key) return cursor;
      cursor++;
    }
  }
  return 0;
}

bool _catalogOwnsKey(ShareCatalog catalog, String? key) {
  if (key == null) return false;
  for (final line in catalog.lines) {
    if (shareServerKey(line) == key) return true;
  }
  return false;
}

/// Keeps [key] when it is still in some list. When this list lost the
/// selection, land on its first remaining row.
int shareRefreshIndex({
  required List<ShareCatalog> catalogs,
  required String catalogId,
  required String? key,
  required bool owned,
}) {
  if (key != null) {
    final found = _indexOfKey(catalogs, key);
    final still = catalogs.any(
      (catalog) => catalog.lines.any((line) => shareServerKey(line) == key),
    );
    if (still) return found;
  }
  if (!owned) return 0;
  var cursor = 0;
  for (final catalog in catalogs) {
    if (catalog.id == catalogId) return cursor;
    cursor += catalog.lines.length;
  }
  return 0;
}

/// `scheme|host:port`. The same server keeps its place after a refresh.
String shareServerKey(String raw) {
  try {
    final link = parseShareLink(raw);
    return '${link.scheme}|${link.endpoint}';
  } on FormatException {
    return raw.trim();
  }
}

List<ParsedShareLink> _linesToKeep(
  List<ParsedShareLink> links, {
  String? hwidMaxDevices,
}) {
  final problem = subscriptionDocumentProblem(
    hwidMaxDevices: hwidMaxDevices,
    links: links,
  );
  if (problem != null) throw SubscriptionDocumentException(problem);
  return dialableShareLinks(links);
}

String _titleFor(String? explicit, List<ParsedShareLink> links) {
  final given = explicit?.trim() ?? '';
  if (given.isNotEmpty) return given;
  if (links.length == 1) return links.single.name;
  return links.first.name;
}

int _idSeq = 0;

/// Clock resolution on Windows can repeat a microsecond, and two catalogs
/// with one id are deleted together.
String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

int _lineCount(List<ShareCatalog> catalogs) {
  var count = 0;
  for (final catalog in catalogs) {
    count += catalog.lines.length;
  }
  return count;
}

ShareCatalog? _catalogAt(_Blob blob, int index) {
  var cursor = 0;
  for (final catalog in blob.catalogs) {
    if (index < cursor + catalog.lines.length) return catalog;
    cursor += catalog.lines.length;
  }
  return blob.catalogs.isEmpty ? null : blob.catalogs.first;
}

int _selectedAfterRemoval(int selected, int start, int length, int nextCount) {
  if (nextCount == 0) return 0;
  if (selected >= start && selected < start + length) {
    return start >= nextCount ? nextCount - 1 : start;
  }
  if (selected >= start + length) return selected - length;
  if (selected >= nextCount) return nextCount - 1;
  return selected;
}

class _Blob {
  const _Blob({this.catalogs = const [], this.selected = 0});

  final List<ShareCatalog> catalogs;
  final int selected;

  factory _Blob.fromJson(Map<dynamic, dynamic> json) {
    final selected = json['selected'];
    final index = selected is int ? selected : 0;
    final rawCatalogs = json['catalogs'];
    if (rawCatalogs is List) {
      return _Blob(
        catalogs: [
          for (final item in rawCatalogs)
            if (item is Map) _catalogFromJson(item),
        ].where((catalog) => catalog.lines.isNotEmpty).toList(),
        selected: index,
      );
    }
    final lines = _strings(json['lines']);
    final hasSplit =
        json.containsKey('manual') || json.containsKey('subscription');
    final List<String> subscription;
    final List<String> manual;
    if (hasSplit) {
      subscription = _strings(json['subscription']);
      manual = _strings(json['manual']);
    } else if (_text(json['url']) != null) {
      subscription = lines;
      manual = const [];
    } else {
      subscription = const [];
      manual = lines;
    }
    final url = _text(json['url']);
    final title = _text(json['title']) ?? '';
    final catalogs = <ShareCatalog>[];
    if (subscription.isNotEmpty || (url != null && manual.isEmpty)) {
      catalogs.add(
        ShareCatalog(
          id: 'legacy-sub',
          title: title.isEmpty ? 'Subscription' : title,
          lines: subscription,
          url: url,
        ),
      );
    }
    if (manual.isNotEmpty) {
      catalogs.add(
        ShareCatalog(
          id: 'legacy-manual',
          title: catalogs.isEmpty && title.isNotEmpty ? title : manual.first,
          lines: manual,
        ),
      );
    }
    if (!hasSplit && url == null && lines.isNotEmpty && catalogs.isEmpty) {
      catalogs.add(
        ShareCatalog(
          id: 'legacy',
          title: title.isEmpty ? lines.first : title,
          lines: lines,
        ),
      );
    }
    return _Blob(catalogs: catalogs, selected: index);
  }

  Map<String, Object?> toJson() => {
        'catalogs': [
          for (final catalog in catalogs)
            {
              'id': catalog.id,
              'title': catalog.title,
              'lines': catalog.lines,
              if (catalog.url != null) 'url': catalog.url,
              if (catalog.etag != null) 'etag': catalog.etag,
              if (catalog.fallbackTitle != null)
                'fallbackTitle': catalog.fallbackTitle,
              if (catalog.titleIsCustom) 'titleIsCustom': true,
              if (catalog.trafficMeta != null)
                'trafficMeta': catalog.trafficMeta,
              if (catalog.updateIntervalHours != null)
                'updateIntervalHours': catalog.updateIntervalHours,
              if (catalog.lastUpdated != null)
                'lastUpdated': catalog.lastUpdated,
              if (catalog.webPageUrl != null) 'webPageUrl': catalog.webPageUrl,
              if (catalog.supportUrl != null) 'supportUrl': catalog.supportUrl,
              if (catalog.announce != null) 'announce': catalog.announce,
              if (catalog.announce != null)
                'announceFrame': catalog.announceFrame,
            },
        ],
        'selected': selected,
      };

  _Blob copyWith({List<ShareCatalog>? catalogs, int? selected}) {
    return _Blob(
      catalogs: catalogs ?? this.catalogs,
      selected: selected ?? this.selected,
    );
  }
}

ShareCatalog _catalogFromJson(Map<dynamic, dynamic> json) {
  return ShareCatalog(
    id: _text(json['id']) ?? _newId(),
    title: _text(json['title']) ?? '',
    lines: _strings(json['lines']),
    url: _text(json['url']),
    etag: _text(json['etag']),
    fallbackTitle: _text(json['fallbackTitle']),
    titleIsCustom: json['titleIsCustom'] == true,
    trafficMeta: _text(json['trafficMeta']),
    updateIntervalHours: json['updateIntervalHours'] is int
        ? json['updateIntervalHours'] as int
        : null,
    lastUpdated: _text(json['lastUpdated']),
    webPageUrl: _text(json['webPageUrl']),
    supportUrl: _text(json['supportUrl']),
    announce: _storedAnnounce(_text(json['announce'])),
    announceFrame: json.containsKey('announceFrame')
        ? json['announceFrame'] == true
        : _text(json['announce']) != null,
  );
}

List<String> _strings(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item,
  ];
}

String? _text(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  return raw.trim();
}

/// A list saved before announcements were decoded may still hold `base64:`.
String? _storedAnnounce(String? raw) {
  if (raw == null) return null;
  return subscriptionNotice(announceHeader: raw).text;
}

/// Show saved servers before refreshing their documents.
///
/// The Servers tab must paint [readLocal] before [refresh]. A refresh that
/// hangs or throws leaves that paint in place, so paste stays reachable
/// while a saved URL times out.
Future<void> paintImportedServers({
  required Future<List<ParsedShareLink>> Function() readLocal,
  required Future<void> Function() refresh,
  required Future<void> Function(List<ParsedShareLink> links) paint,
}) async {
  List<ParsedShareLink> local;
  try {
    local = await readLocal();
  } catch (_) {
    await paint(const []);
    return;
  }
  await paint(local);
  try {
    await refresh();
  } catch (_) {
    return;
  }
  try {
    await paint(await readLocal());
  } catch (_) {
    // The first paint already cleared the spinner.
  }
}
