import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/legal/third_party_notices.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';

/// One row of the licence list: a package, its body, and the section it
/// belongs to. Flutter's stock LicensePage is a wall of package names in a
/// typeface the app does not use; this keeps the product's own paper, search
/// and the same engine notice the test already guards.
class _LicenseItem {
  const _LicenseItem({
    required this.name,
    required this.body,
    required this.engine,
    this.subtitle,
  });

  final String name;
  final String body;
  final bool engine;
  final String? subtitle;
}

class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key});

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  final _search = TextEditingController();
  List<_LicenseItem>? _items;
  String _query = '';
  String _version = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      setState(() => _query = _search.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Engine and fonts are read first: they are the two entries this page is
    // actually for, and they must not wait behind the hundreds of package
    // licences LicenseRegistry streams. The registry is merged afterwards.
    final local = <_LicenseItem>[];
    try {
      final text = await rootBundle.loadString(thirdPartyNoticesAsset);
      local.add(_LicenseItem(name: 'hy2bind', body: text, engine: true));
    } catch (_) {
      // A missing notice asset must not take the page down.
    }

    // The two text faces ship under SIL OFL; their notices are assets beside
    // the fonts, not part of LicenseRegistry.
    for (final font in const [
      ('Onest', 'assets/fonts/OFL-Onest.txt'),
      ('JetBrains Mono', 'assets/fonts/OFL-JetBrainsMono.txt'),
    ]) {
      try {
        final body = await rootBundle.loadString(font.$2);
        local.add(
          _LicenseItem(
            name: font.$1,
            body: body,
            engine: false,
            subtitle: 'SIL OFL 1.1',
          ),
        );
      } catch (_) {
        // A missing notice asset must not take the page down.
      }
    }

    // Show the engine at once; the platform channel for the version can be slow
    // or absent in a widget test, and it must not hold the list behind a
    // spinner.
    if (mounted) setState(() => _items = local);

    var version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Footer stays empty when the platform channel is unavailable.
    }
    if (mounted && version.isNotEmpty) {
      setState(() => _version = version);
    }

    final byName = <String, StringBuffer>{};
    for (final item in local) {
      byName[item.name] = StringBuffer(item.body);
    }
    await for (final entry in LicenseRegistry.licenses) {
      final name = entry.packages.join(', ').trim();
      if (name.isEmpty || byName.containsKey(name)) continue;
      final body = entry.paragraphs.map((p) => p.text).join('\n\n').trim();
      if (body.isEmpty) continue;
      byName.putIfAbsent(name, StringBuffer.new).write(body);
      byName[name]!.write('\n\n');
    }

    final merged = <_LicenseItem>[
      for (final entry in byName.entries)
        _LicenseItem(
          name: entry.key,
          body: entry.value.toString().trim(),
          engine: entry.key.toLowerCase().contains('hy2bind'),
          subtitle: entry.key == 'Onest' || entry.key == 'JetBrains Mono'
              ? 'SIL OFL 1.1'
              : null,
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (!mounted) return;
    setState(() => _items = merged);
  }

  List<_LicenseItem> get _visible {
    final all = _items ?? const <_LicenseItem>[];
    final q = _query;
    if (q.isEmpty) return all;
    return [
      for (final item in all)
        if (item.name.toLowerCase().contains(q) ||
            item.body.toLowerCase().contains(q))
          item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final sheet = dark ? AppBrand.surfaceDark : AppBrand.paperLight;
    final items = _visible;
    final engine = items.where((i) => i.engine).toList();
    final packages =
        items.where((i) => !i.engine && i.subtitle == null).toList();
    final fonts = items.where((i) => i.subtitle != null).toList();

    return Scaffold(
      backgroundColor: sheet,
      appBar: AppBar(
        backgroundColor: sheet,
        surfaceTintColor: sheet,
        title: Text(l.licensesTitle),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _items == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppBrand.pageGutter,
                  4,
                  AppBrand.pageGutter,
                  28,
                ),
                children: [
                  Text(
                    l.appTitle,
                    style: theme.textTheme.headlineMedium,
                  ),
                  if (_version.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      l.settingsVersion(_version),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: l.licensesSearch,
                      prefixIcon: const AppIcon(AppIcons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _search.clear,
                              icon: const AppIcon(AppIcons.x),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        l.licensesNoResults,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  if (engine.isNotEmpty) ...[
                    _SectionLabel(l.licensesEngine),
                    _LicenseCard(
                      items: engine,
                      onTap: (item) => _open(context, item),
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (packages.isNotEmpty) ...[
                    _SectionLabel(l.licensesPackages),
                    _LicenseCard(
                      items: packages,
                      onTap: (item) => _open(context, item),
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (fonts.isNotEmpty) ...[
                    _SectionLabel(l.licensesFonts),
                    _LicenseCard(
                      items: fonts,
                      onTap: (item) => _open(context, item),
                    ),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
      ),
    );
  }

  void _open(BuildContext context, _LicenseItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LicenseDetailScreen(item: item),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight,
        ),
      ),
    );
  }
}

class _LicenseCard extends StatelessWidget {
  const _LicenseCard({required this.items, required this.onTap});

  final List<_LicenseItem> items;
  final ValueChanged<_LicenseItem> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = theme.colorScheme.outline;
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        side: BorderSide(color: line.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: line.withValues(alpha: 0.4)),
            ListTile(
              title: Text(
                items[i].name,
                style: theme.textTheme.titleMedium,
              ),
              subtitle: items[i].subtitle == null
                  ? null
                  : Text(items[i].subtitle!, style: theme.textTheme.bodySmall),
              trailing: const AppIcon(AppIcons.chevronRight, size: 16),
              onTap: () => onTap(items[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _LicenseDetailScreen extends StatelessWidget {
  const _LicenseDetailScreen({required this.item});

  final _LicenseItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheet = theme.brightness == Brightness.dark
        ? AppBrand.surfaceDark
        : AppBrand.paperLight;
    return Scaffold(
      backgroundColor: sheet,
      appBar: AppBar(
        backgroundColor: sheet,
        surfaceTintColor: sheet,
        title: Text(item.name),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppBrand.pageGutter,
            8,
            AppBrand.pageGutter,
            28,
          ),
          child: SelectableText(
            item.body,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
          ),
        ),
      ),
    );
  }
}
