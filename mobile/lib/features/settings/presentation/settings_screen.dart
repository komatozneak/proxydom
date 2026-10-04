import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/config.dart';
import '../../../core/diagnostics/tunnel_log_level.dart';
import '../../../core/diagnostics/tunnel_log_prefs.dart';
import '../../../core/diagnostics/ui_log.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/support_contact.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/app_switch.dart';
import '../../../core/widgets/proxydom_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../application/locale_provider.dart';
import '../application/theme_mode_provider.dart';
import '../data/vpn_notification_prefs.dart';
import '../data/qs_tile_prefs.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool? _notifEnabled;
  bool _notifLoading = false;
  bool _qsAdding = false;
  bool _qsTileAdded = false;
  String _versionLabel = '';
  TunnelLogLevel _logLevel = TunnelLogLevel.info;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && QsTilePrefs.isSupported) {
      _loadQsTileAdded();
    }
  }

  Future<void> _bootstrap() async {
    final futures = <Future<void>>[
      _loadVersion(),
      _loadLogLevel(),
    ];
    if (VpnNotificationPrefs.isSupported) {
      futures.add(_loadNotif());
    }
    if (QsTilePrefs.isSupported) {
      futures.add(_loadQsTileAdded());
    }
    await Future.wait(futures);
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _versionLabel = info.version);
    } catch (_) {
      // ignore ? footer stays empty
    }
  }

  Future<void> _loadNotif() async {
    final enabled = await VpnNotificationPrefs.isEnabled();
    if (!mounted) return;
    setState(() => _notifEnabled = enabled);
  }

  Future<void> _onNotifChanged(bool value) async {
    setState(() {
      _notifLoading = true;
      _notifEnabled = value;
    });
    await VpnNotificationPrefs.setEnabled(value);
    UiLog.action('settings', 'notification', extra: {'on': value});
    if (!mounted) return;
    setState(() => _notifLoading = false);
  }

  Future<void> _loadQsTileAdded() async {
    final added = await QsTilePrefs.isAdded();
    if (!mounted) return;
    setState(() => _qsTileAdded = added);
  }

  Future<void> _onAddQsTile() async {
    if (_qsAdding) return;
    if (_qsTileAdded) {
      await _showQsTileRemoveDialog();
      return;
    }
    setState(() => _qsAdding = true);
    final result = await QsTilePrefs.requestAdd();
    UiLog.action('settings', 'qs_tile', result: result);
    if (!mounted) return;
    final added = result == 'added' || result == 'already_added';
    setState(() {
      _qsAdding = false;
      if (added) _qsTileAdded = true;
    });
    if (result == 'already_added') {
      await _showQsTileRemoveDialog();
      return;
    }
    final l = AppL10n.of(context);
    final message = switch (result) {
      'added' => l.settingsQsTileAdded,
      'not_added' => l.settingsQsTileNotAdded,
      _ => l.settingsQsTileManual,
    };
    showProxyDomSnackBar(context, message);
  }

  Future<void> _showQsTileRemoveDialog() async {
    final l = AppL10n.of(context);
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsQsTileRemoveTitle),
        content: Text(l.settingsQsTileRemoveBody),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.settingsQsTileRemoveAck),
          ),
        ],
      ),
    );
  }

  Future<void> _loadLogLevel() async {
    final level = await TunnelLogPrefs.read();
    if (!mounted) return;
    setState(() => _logLevel = level);
  }

  String _logLevelLabel(AppL10n l, TunnelLogLevel level) => switch (level) {
        TunnelLogLevel.off => l.tunnelLogsLevelOff,
        TunnelLogLevel.error => l.tunnelLogsLevelError,
        TunnelLogLevel.warn => l.tunnelLogsLevelWarn,
        TunnelLogLevel.info => l.tunnelLogsLevelInfo,
        TunnelLogLevel.debug => l.tunnelLogsLevelDebug,
      };

  String _themeModeLabel(AppL10n l, ThemeMode mode) => switch (mode) {
        ThemeMode.light => l.settingsThemeLight,
        ThemeMode.dark => l.settingsThemeDark,
        ThemeMode.system => l.settingsThemeSystem,
      };

  String _localeLabel(AppL10n l, Locale locale) =>
      switch (locale.languageCode) {
        'en' => l.settingsLanguageEnglish,
        _ => l.settingsLanguageRussian,
      };

  Future<void> _pickThemeMode() async {
    final l = AppL10n.of(context);
    final current = ref.read(themeModeProvider).valueOrNull ?? ThemeMode.system;
    // Auto → Light → Dark (ThemeMode.values is system, light, dark).
    const options = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    final chosen = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in options)
                ListTile(
                  title: Text(_themeModeLabel(l, mode)),
                  trailing: mode == current
                      ? Icon(
                          Icons.check,
                          color: Theme.of(ctx).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(ctx).pop(mode),
                ),
            ],
          ),
        );
      },
    );
    if (chosen == null || !mounted) return;
    UiLog.action('settings', 'theme', extra: {'mode': chosen.name});
    await ref.read(themeModeProvider.notifier).setMode(chosen);
  }

  Future<void> _pickLocale() async {
    final l = AppL10n.of(context);
    final current =
        ref.read(localeProvider).valueOrNull ?? Localizations.localeOf(context);
    const options = [Locale('ru'), Locale('en')];
    final chosen = await showModalBottomSheet<Locale>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final locale in options)
                ListTile(
                  title: Text(_localeLabel(l, locale)),
                  trailing: locale.languageCode == current.languageCode
                      ? Icon(
                          Icons.check,
                          color: Theme.of(ctx).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(ctx).pop(locale),
                ),
            ],
          ),
        );
      },
    );
    if (chosen == null || !mounted) return;
    UiLog.action('settings', 'locale', extra: {'lang': chosen.languageCode});
    await ref.read(localeProvider.notifier).setLocale(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final showNotif = VpnNotificationPrefs.isSupported;
    final showNoVpn = androidPerAppSplit || windowsDesktop;
    final notifOn = _notifEnabled ?? true;
    final themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final locale = ref.watch(localeProvider).valueOrNull ??
        Localizations.localeOf(context);
    final localeLabel = _localeLabel(l, locale);
    // A settings row is a line of text with a control on the right. Across a
    // 1500px window that line is unreadable, so the page keeps a measure and
    // the rest of the window stays empty paper — the way a desktop settings
    // page behaves.
    final page = ListView(
      padding: EdgeInsets.fromLTRB(
        windowsDesktop ? AppBrand.pageGutterWide : AppBrand.pageGutter,
        windowsDesktop ? 34 : 12,
        windowsDesktop ? AppBrand.pageGutterWide : AppBrand.pageGutter,
        32,
      ),
      children: [
        Text(
          l.settingsTitle,
          style: theme.textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 20),
        ..._settingsSections(
          l: l,
          showNotif: showNotif,
          showNoVpn: showNoVpn,
          notifOn: notifOn,
          localeLabel: localeLabel,
          themeMode: themeMode,
        ),
        const SizedBox(height: 28),
        if (_versionLabel.isNotEmpty)
          Text(
            l.settingsVersion(_versionLabel),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: windowsDesktop
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 780),
                  child: page,
                ),
              )
            : page,
      ),
    );
  }

  List<Widget> _settingsSections({
    required AppL10n l,
    required bool showNotif,
    required bool showNoVpn,
    required bool notifOn,
    required String localeLabel,
    required ThemeMode themeMode,
  }) {
    final sections = <({String title, List<Widget> rows})>[
      (
        title: l.settingsSupport,
        rows: [
          if (AppConfig.authAnonymous)
            _SettingsRow(
              icon: AppIcons.siteCustom,
              title: l.settingsSupport,
              subtitle: AppConfig.supportEmail,
              onTap: () {
                SupportContact.open();
              },
            ),
        ],
      ),
      (
        title: l.settingsSectionConnection,
        rows: [
          _SettingsRow(
            icon: AppIcons.bug,
            title: l.tunnelLogsTitle,
            subtitle: _logLevelLabel(l, _logLevel),
            onTap: () async {
              UiLog.action('settings', 'logs');
              await context.push('/settings/logs');
              if (mounted) await _loadLogLevel();
            },
          ),
          if (showNotif)
            _SettingsRow(
              icon: AppIcons.notifications,
              title: l.settingsVpnNotificationTitle,
              subtitle: l.settingsVpnNotificationHint,
              trailing: AppSwitch(
                value: notifOn,
                onChanged: _notifLoading || _notifEnabled == null
                    ? null
                    : _onNotifChanged,
              ),
            ),
          if (showNotif && QsTilePrefs.isSupported)
            _SettingsRow(
              leading: const _QsTileMonoIcon(),
              title: l.settingsQsTileTitle,
              subtitle: _qsTileAdded
                  ? l.settingsQsTileAddedHint
                  : l.settingsQsTileHint,
              onTap: _qsAdding ? null : _onAddQsTile,
              trailing: _qsAdding
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _qsTileAdded
                      ? Text(
                          l.settingsQsTileRemove,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                        )
                      : null,
            ),
          if (showNoVpn)
            _SettingsRow(
              icon: AppIcons.sliders,
              title: l.settingsNoVpn,
              subtitle: l.settingsNoVpnHint,
              onTap: () {
                UiLog.action('settings', 'no_vpn');
                context.go('/settings/no-vpn');
              },
            ),
        ],
      ),
      (
        title: l.settingsSectionApp,
        rows: [
          _SettingsRow(
            icon: AppIcons.globe,
            title: l.settingsLanguage,
            subtitle: localeLabel,
            onTap: _pickLocale,
          ),
          _SettingsRow(
            icon: AppIcons.palette,
            title: l.settingsAppearance,
            subtitle: _themeModeLabel(l, themeMode),
            onTap: _pickThemeMode,
          ),
        ],
      ),
    ];
    final out = <Widget>[];
    for (final section in sections) {
      if (section.rows.isEmpty) continue;
      if (out.isNotEmpty) out.add(const SizedBox(height: 20));
      out.add(_SectionLabel(section.title));
      out.add(_SettingsCard(children: _divided(section.rows)));
    }
    return out;
  }

  List<Widget> _divided(List<Widget> rows) {
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) out.add(const _CardDivider());
      out.add(rows[i]);
    }
    return out;
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
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 9),
      child: Row(
        children: [
          // The same terminal voice as the home head: a rule and a tracked
          // label. A title in sentence case here read as a different app.
          Container(width: 2, height: 11, color: AppBrand.mascotGold.withValues(alpha: 0.75)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                letterSpacing: 2.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: (dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight)
                  .withValues(alpha: 0.16),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      clip: true,
      child: Column(children: children),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 62),
      child: Container(
        height: 1,
        color: dark
            ? AppBrand.lightSource.withValues(alpha: 0.06)
            : AppBrand.shadeSource.withValues(alpha: 0.07),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    this.icon,
    this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  }) : assert(icon != null || leading != null);

  final IconData? icon;
  final Widget? leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // The subtitle was allowed to run to four lines under a floating switch,
    // which broke the row rhythm on every card. Two lines, then it stops.
    const maxLines = 2;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            leading ?? _RowGlyph(child: AppIcon(icon!, size: 19)),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 15.5,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ] else if (onTap != null) ...[
              const SizedBox(width: 10),
              AppIcon(
                AppIcons.chevronRight,
                size: 16,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The icon plate every settings row carries. A milled chip, not a flat tint.
class _RowGlyph extends StatelessWidget {
  const _RowGlyph({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? AppBrand.surfaceSunkDark : AppBrand.honeySurface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: dark
              ? AppBrand.lightSource.withValues(alpha: 0.06)
              : AppBrand.shadeSource.withValues(alpha: 0.05),
        ),
      ),
      child: child,
    );
  }
}

/// Living House from `ic_launcher_monochrome`, tinted like the other row icons.
class _QsTileMonoIcon extends StatelessWidget {
  const _QsTileMonoIcon();

  static const _asset = 'assets/icon/ic_launcher_monochrome.png';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.iconTheme.color ?? theme.colorScheme.onSurface;
    return _RowGlyph(
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        child: Image.asset(
          _asset,
          width: 19,
          height: 19,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
