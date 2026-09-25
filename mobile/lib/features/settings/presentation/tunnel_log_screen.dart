import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/diagnostics/app_log_buffer.dart';
import '../../../core/diagnostics/product_log.dart';
import '../../../core/diagnostics/tunnel_log_badge.dart';
import '../../../core/diagnostics/tunnel_log_format.dart';
import '../../../core/diagnostics/tunnel_log_level.dart';
import '../../../core/diagnostics/tunnel_log_prefs.dart';
import '../../../core/diagnostics/tunnel_log_redact.dart';
import '../../../core/diagnostics/ui_log.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../vpn/data/vpn_controller.dart';

enum _LogGroup { all, session, ui, core, dns, fetch, network }

/// Tunnel log viewer. Categories are only the groups this app records.
class TunnelLogScreen extends StatefulWidget {
  const TunnelLogScreen({super.key});

  @override
  State<TunnelLogScreen> createState() => _TunnelLogScreenState();
}

class _TunnelLogScreenState extends State<TunnelLogScreen> {
  TunnelLogLevel _level = TunnelLogLevel.info;
  _LogGroup _group = _LogGroup.all;
  String _query = '';
  List<String> _lines = const [];
  List<String>? _frozen;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (_level == TunnelLogLevel.off) return;
    final level = await TunnelLogPrefs.read();
    final core =
        await VpnController.instance.getVpnCoreStderrTail(maxLines: 400);
    final coreLines = (core == null || core.trim().isEmpty)
        ? const <String>[]
        : core.split('\n').where((line) => line.isNotEmpty);
    if (!mounted) return;
    final merged = [...AppLogBuffer.instance.recentLines(), ...coreLines]
      ..sort(_byTime);
    setState(() {
      _level = level;
      _lines = merged;
      _frozen = null;
    });
  }

  Future<void> _setLevel(TunnelLogLevel level) async {
    if (level == TunnelLogLevel.off) {
      final shot = List<String>.of(_visible);
      await TunnelLogPrefs.write(level);
      if (!mounted) return;
      setState(() {
        _level = level;
        _frozen = shot;
      });
      return;
    }
    await TunnelLogPrefs.write(level);
    if (!mounted) return;
    setState(() {
      _level = level;
      _frozen = null;
    });
    await _reload();
  }

  List<String> get _visible {
    if (_frozen != null) return _frozen!;
    final q = _query.trim().toLowerCase();
    return [
      for (final line in _lines)
        if (_matchesGroup(line) &&
            _matchesLevel(line) &&
            (q.isEmpty || line.toLowerCase().contains(q)))
          line,
    ];
  }

  bool _matchesLevel(String line) {
    final recorded = RegExp(r'\[(error|warn|info|debug)\]').firstMatch(line);
    final name = recorded?.group(1) ?? 'info';
    return _level.showsLine(name);
  }

  bool _matchesGroup(String line) {
    return switch (_group) {
      _LogGroup.all => true,
      _LogGroup.session => line.contains('[vpn]'),
      _LogGroup.ui => line.contains('[ui]'),
      _LogGroup.core => line.contains('[hy2]') ||
          line.contains('[core]') ||
          line.contains('core.xray'),
      _LogGroup.dns => line.contains('dns='),
      _LogGroup.fetch => line.contains('[doc]'),
      _LogGroup.network => line.contains('[net]'),
    };
  }

  int _byTime(String a, String b) {
    final left = tunnelLogTime(a);
    final right = tunnelLogTime(b);
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }

  Future<void> _copy(List<String> lines) async {
    UiLog.action(
      'logs',
      'export',
      level: ProductLogLevel.info,
      extra: {'lines': lines.length},
    );
    final text = lines.isEmpty ? '' : redactTunnelLog(lines.join('\n'));
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showTeremokSnackBar(context, AppL10n.of(context).tunnelLogsCopied);
  }

  Future<void> _delete() async {
    UiLog.action('logs', 'clear', level: ProductLogLevel.info);
    AppLogBuffer.instance.clear();
    await AppLogBuffer.instance.flushPersist();
    await VpnController.instance.clearCoreLog();
    if (!mounted) return;
    setState(() {
      _lines = const [];
      _frozen = _level == TunnelLogLevel.off ? const [] : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final visible = _visible;
    final sheet = theme.brightness == Brightness.dark
        ? AppBrand.surfaceDark
        : AppBrand.surfaceElevatedLight;
    return Scaffold(
      backgroundColor: sheet,
      appBar: AppBar(
        backgroundColor: sheet,
        surfaceTintColor: sheet,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const AppIcon(AppIcons.x),
        ),
        title: Text(l.tunnelLogsTitle),
        actions: [
          PopupMenuButton<TunnelLogLevel>(
            initialValue: _level,
            onSelected: _setLevel,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _levelLabel(l, _level),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppBrand.secondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            itemBuilder: (context) => [
              for (final level in TunnelLogLevel.values)
                PopupMenuItem(
                  value: level,
                  child: Text(_levelLabel(l, level)),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: l.tunnelLogsSearch,
                prefixIcon: const AppIcon(AppIcons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final group in _LogGroup.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_groupLabel(l, group)),
                        selected: _group == group,
                        onSelected: (_) => setState(() => _group = group),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(child: Text(l.tunnelLogsEmpty))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: visible.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _LogLine(line: visible[index]),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _action(
                        AppIcons.refresh,
                        l.tunnelLogsRefresh,
                        _reload,
                      ),
                    ),
                    Expanded(
                      child: _action(
                        AppIcons.clipboard,
                        l.tunnelLogsCopy,
                        () => _copy(visible),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _action(
                        AppIcons.download,
                        l.tunnelLogsExport,
                        () => _copy(_lines),
                      ),
                    ),
                    Expanded(
                      child: _action(
                        AppIcons.trash,
                        l.tunnelLogsDelete,
                        _delete,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: AppIcon(icon, size: 18, color: AppBrand.secondary),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  String _levelLabel(AppL10n l, TunnelLogLevel level) => switch (level) {
        TunnelLogLevel.off => l.tunnelLogsLevelOff,
        TunnelLogLevel.error => l.tunnelLogsLevelError,
        TunnelLogLevel.warn => l.tunnelLogsLevelWarn,
        TunnelLogLevel.info => l.tunnelLogsLevelInfo,
        TunnelLogLevel.debug => l.tunnelLogsLevelDebug,
      };

  String _groupLabel(AppL10n l, _LogGroup group) => switch (group) {
        _LogGroup.all => l.tunnelLogsAll,
        _LogGroup.session => l.tunnelLogsSession,
        _LogGroup.ui => l.tunnelLogsUi,
        _LogGroup.core => l.tunnelLogsCore,
        _LogGroup.dns => l.tunnelLogsDns,
        _LogGroup.fetch => l.tunnelLogsFetch,
        _LogGroup.network => l.tunnelLogsNetwork,
      };
}

/// Level token as a colored chip. The message stays the body color.
class _LogLine extends StatelessWidget {
  const _LogLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    final badge = tunnelLogBadge(line);
    if (badge == null) {
      return Text(line, style: style);
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: badge.before),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _LevelChip(label: badge.label),
          ),
          TextSpan(text: badge.after),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (label) {
      'error' => (AppBrand.destructive, AppBrand.accentOnDark),
      'warn' => (AppBrand.caution, AppBrand.primary),
      'debug' => (AppBrand.warning, AppBrand.accentOnDark),
      _ => (AppBrand.secondary, AppBrand.accentOnDark),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          child: Text(
            '[$label]',
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              height: 1.15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
