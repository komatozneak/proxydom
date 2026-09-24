import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/diagnostics/app_log_buffer.dart';
import '../../../core/diagnostics/tunnel_log_level.dart';
import '../../../core/diagnostics/tunnel_log_prefs.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';

enum _LogGroup { all, session, network }

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

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final level = await TunnelLogPrefs.read();
    if (!mounted) return;
    setState(() {
      _level = level;
      _lines = AppLogBuffer.instance.recentLines();
    });
  }

  Future<void> _setLevel(TunnelLogLevel level) async {
    await TunnelLogPrefs.write(level);
    if (!mounted) return;
    setState(() => _level = level);
  }

  List<String> get _visible {
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
    if (_level == TunnelLogLevel.off) return true;
    final recorded = RegExp(r'\[(error|warn|info|debug)\]').firstMatch(line);
    final name = recorded?.group(1) ?? 'info';
    return _level.allows(name);
  }

  bool _matchesGroup(String line) {
    return switch (_group) {
      _LogGroup.all => true,
      _LogGroup.session => line.contains('vpn.'),
      _LogGroup.network => line.contains('net.') ||
          line.contains('api.') ||
          line.contains('iface'),
    };
  }

  Future<void> _copy(List<String> lines) async {
    final text = lines.isEmpty ? '' : lines.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showTeremokSnackBar(context, AppL10n.of(context).tunnelLogsCopied);
  }

  Future<void> _delete() async {
    AppLogBuffer.instance.clear();
    await AppLogBuffer.instance.flushPersist();
    if (!mounted) return;
    setState(() => _lines = const []);
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
          Expanded(
            child: visible.isEmpty
                ? Center(child: Text(l.tunnelLogsEmpty))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: visible.length,
                    itemBuilder: (context, index) => Text(
                      visible[index],
                      style: theme.textTheme.bodySmall,
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
        _LogGroup.network => l.tunnelLogsNetwork,
      };
}
