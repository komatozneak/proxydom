import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/install_id_storage.dart';
import '../../../core/support_contact.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/application/logout_handler.dart';
import '../../home/application/vpn_provider.dart';
import '../application/locale_provider.dart';
import '../application/subscription_status_provider.dart';
import '../application/theme_mode_provider.dart';
import '../data/access_status_copy.dart';
import '../data/auto_reconnect_prefs.dart';
import '../data/subscription_status.dart';
import '../data/vpn_notification_prefs.dart';
import '../data/qs_tile_prefs.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _logoutInProgress = false;
  String? _installId;
  bool? _notifEnabled;
  bool _notifLoading = false;
  bool _qsAdding = false;
  bool? _autoReconnect;
  bool _autoReconnectLoading = false;
  bool _reportSending = false;
  String _versionLabel = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final futures = <Future<void>>[
      _loadVersion(),
      _loadInstallId(),
    ];
    if (!hideInAppPlategaCheckout) {
      futures.add(_loadAutoReconnect());
    }
    if (VpnNotificationPrefs.isSupported) {
      futures.add(_loadNotif());
    }
    await Future.wait(futures);
  }

  Future<void> _loadInstallId() async {
    try {
      final id = await InstallIdStorage.instance.getOrCreate();
      if (!mounted) return;
      setState(() => _installId = id);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _copyInstallId() async {
    final id = _installId;
    if (id == null || id.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    showTeremokSnackBar(context, AppL10n.of(context).settingsDeviceIdCopied);
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

  Future<void> _loadAutoReconnect() async {
    final enabled = await AutoReconnectPrefs.isEnabled();
    if (!mounted) return;
    setState(() => _autoReconnect = enabled);
  }

  Future<void> _onNotifChanged(bool value) async {
    setState(() {
      _notifLoading = true;
      _notifEnabled = value;
    });
    await VpnNotificationPrefs.setEnabled(value);
    if (!mounted) return;
    setState(() => _notifLoading = false);
  }

  Future<void> _onAddQsTile() async {
    if (_qsAdding) return;
    setState(() => _qsAdding = true);
    final result = await QsTilePrefs.requestAdd();
    if (!mounted) return;
    setState(() => _qsAdding = false);
    final l = AppL10n.of(context);
    final message = switch (result) {
      'added' => l.settingsQsTileAdded,
      'already_added' => l.settingsQsTileAlreadyAdded,
      'not_added' => l.settingsQsTileNotAdded,
      _ => l.settingsQsTileManual,
    };
    showTeremokSnackBar(context, message);
  }

  Future<void> _onAutoReconnectChanged(bool value) async {
    setState(() {
      _autoReconnectLoading = true;
      _autoReconnect = value;
    });
    await AutoReconnectPrefs.setEnabled(value);
    if (!mounted) return;
    setState(() => _autoReconnectLoading = false);
  }

  String _formatAccessDate(DateTime dt) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat('d MMMM y', locale).format(dt);
  }

  String _accessTitle(AppL10n l, AsyncValue<SubscriptionStatus> async) {
    return async.when(
      data: (s) {
        switch (accessCopyKind(s)) {
          case AccessCopyKind.paidOrTrial:
            return l.settingsSubscriptionActive;
          case AccessCopyKind.cancelled:
            return l.settingsSubscriptionActiveUntil(
              _formatAccessDate(s.expiresAt!),
            );
          case AccessCopyKind.closedBeta:
            return l.settingsAccessBetaTitle;
          case AccessCopyKind.free:
            return l.settingsAccessFreeTitle;
          case AccessCopyKind.none:
            return l.settingsAccessNoneTitle;
          case AccessCopyKind.generic:
            return l.settingsSubscription;
        }
      },
      loading: () => l.settingsSubscription,
      error: (_, __) => l.settingsSubscription,
    );
  }

  String _accessSubtitle(AppL10n l, AsyncValue<SubscriptionStatus> async) {
    return async.when(
      data: (s) {
        switch (accessCopyKind(s)) {
          case AccessCopyKind.paidOrTrial:
            if (s.expiresAt != null) {
              return l
                  .settingsAccessActiveUntil(_formatAccessDate(s.expiresAt!));
            }
            return l.settingsAccessBetaSubtitle;
          case AccessCopyKind.cancelled:
            return l.settingsAccessCancelledSubtitle;
          case AccessCopyKind.closedBeta:
            if (s.expiresAt != null) {
              return l
                  .settingsAccessActiveUntil(_formatAccessDate(s.expiresAt!));
            }
            return l.settingsAccessBetaSubtitle;
          case AccessCopyKind.free:
            return l.settingsAccessFreeSubtitle;
          case AccessCopyKind.none:
            return l.settingsAccessNoneSubtitle;
          case AccessCopyKind.generic:
            if (s.status == 'expired' && s.expiresAt != null) {
              return l
                  .settingsAccessActiveUntil(_formatAccessDate(s.expiresAt!));
            }
            return l.settingsAccessNoneSubtitle;
        }
      },
      loading: () => '?',
      error: (_, __) => l.settingsSubscriptionLoadError,
    );
  }

  Future<void> _onLogoutPressed() async {
    final l = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.logoutConfirmTitle),
        content: Text(l.logoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppBrand.destructive),
            child: Text(l.logoutTooltip),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _logoutInProgress = true);
    final result = await ref.read(logoutHandlerProvider).logout();
    if (!mounted) return;
    setState(() => _logoutInProgress = false);

    if (result is LogoutPartialFailure) {
      showTeremokSnackBar(context, '${l.logoutWarning}: ${result.message}');
    }
    // Anonymous: re-check entitlement → locked if unpaid.
    if (AppConfig.authAnonymous) {
      context.go('/gate');
    }
    // Phone path: GoRouter redirects to /login via refreshListenable.
  }

  Future<void> _onSendReportPressed() async {
    final l = AppL10n.of(context);
    setState(() => _reportSending = true);
    try {
      final auth = ref.read(authProvider).valueOrNull;
      final vpn = ref.read(vpnProvider);
      final notifier = ref.read(vpnProvider.notifier);
      final service = DiagnosticsService();
      final report = await service.buildReport(
        authState: auth ?? const AuthStateUnauthenticated(),
        vpnUi: vpn,
        cachedConfig: notifier.config,
        autoWinnerId: notifier.autoWinnerId,
        autoWinnerLabel: notifier.displayLabel,
        lastProve: notifier.lastProveSummary,
        catalogHost: notifier.catalogHost,
      );
      final saved = await DiagnosticsService.persistLocal(report);
      await Clipboard.setData(ClipboardData(text: saved.body));
      if (!mounted) return;
      showTeremokSnackBar(context, l.settingsReportCopied);
    } catch (_) {
      if (!mounted) return;
      showTeremokSnackBar(context, l.settingsReportFailed);
    } finally {
      if (mounted) setState(() => _reportSending = false);
    }
  }

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
    await ref.read(localeProvider.notifier).setLocale(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final showNotif = VpnNotificationPrefs.isSupported;
    final showAutoReconnect = !hideInAppPlategaCheckout;
    final showNoVpn = !hideInAppPlategaCheckout;
    final notifOn = _notifEnabled ?? true;
    final autoOn = _autoReconnect ?? false;
    final showConnectionSection = showAutoReconnect || showNotif || showNoVpn;
    final subAsync = ref.watch(subscriptionStatusProvider);
    final themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final locale = ref.watch(localeProvider).valueOrNull ??
        Localizations.localeOf(context);
    final localeLabel = _localeLabel(l, locale);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              l.settingsTitle,
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel(l.settingsSectionAccount),
            _SettingsCard(
              children: [
                if (!hideInAppPlategaCheckout)
                  _SettingsRow(
                    leading: _AccessStatusGlyph(status: subAsync),
                    title: _accessTitle(l, subAsync),
                    subtitle: _accessSubtitle(l, subAsync),
                    onTap: () => context.push('/settings/account'),
                    trailing: subAsync.when(
                      data: (_) =>
                          const AppIcon(AppIcons.chevronRight, size: 18),
                      loading: () => const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (_, __) => TextButton(
                        onPressed: () => ref
                            .read(subscriptionStatusProvider.notifier)
                            .refresh(),
                        child: Text(l.homeRetry),
                      ),
                    ),
                  ),
                if (AppConfig.authAnonymous) ...[
                  if (!hideInAppPlategaCheckout) ...[
                    const _CardDivider(),
                    _SettingsRow(
                      icon: AppIcons.devices,
                      title: l.settingsDevices,
                      subtitle: l.settingsDevicesHint,
                      onTap: () => context.push('/settings/devices'),
                    ),
                  ],
                  if (!hideInAppPlategaCheckout) const _CardDivider(),
                  _SettingsRow(
                    icon: AppIcons.siteTelegram,
                    title: l.settingsSupport,
                    subtitle: hideInAppPlategaCheckout
                        ? l.settingsSupportHintIos
                        : l.settingsSupportHint,
                    onTap: () {
                      SupportContact.open(screen: 'Настройки');
                    },
                  ),
                ],
                const _CardDivider(),
                _SettingsRow(
                  icon: AppIcons.bug,
                  title: l.settingsSendReport,
                  subtitle: l.settingsSendReportHint,
                  onTap: _reportSending ? null : _onSendReportPressed,
                  trailing: _reportSending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ],
            ),
            if (showConnectionSection) ...[
              const SizedBox(height: 20),
              _SectionLabel(l.settingsSectionConnection),
              _SettingsCard(
                children: [
                  if (showAutoReconnect)
                    _SettingsRow(
                      icon: AppIcons.refresh,
                      title: l.settingsAutoReconnect,
                      subtitle: l.settingsAutoReconnectHint,
                      trailing: Switch(
                        value: autoOn,
                        onChanged:
                            _autoReconnectLoading || _autoReconnect == null
                                ? null
                                : _onAutoReconnectChanged,
                      ),
                    ),
                  if (showNotif) ...[
                    if (showAutoReconnect) const _CardDivider(),
                    _SettingsRow(
                      icon: AppIcons.notifications,
                      title: l.settingsVpnNotificationTitle,
                      subtitle: l.settingsVpnNotificationHint,
                      trailing: Switch(
                        value: notifOn,
                        onChanged: _notifLoading || _notifEnabled == null
                            ? null
                            : _onNotifChanged,
                      ),
                    ),
                    if (QsTilePrefs.isSupported) ...[
                      const _CardDivider(),
                      _SettingsRow(
                        icon: AppIcons.house,
                        title: l.settingsQsTileTitle,
                        subtitle: l.settingsQsTileHint,
                        onTap: _qsAdding ? null : _onAddQsTile,
                        trailing: _qsAdding
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                      ),
                    ],
                  ],
                  if (showNoVpn) ...[
                    if (showAutoReconnect || showNotif) const _CardDivider(),
                    _SettingsRow(
                      icon: AppIcons.sliders,
                      title: l.settingsNoVpn,
                      subtitle: l.settingsNoVpnHint,
                      onTap: () => context.go('/settings/no-vpn'),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 20),
            _SectionLabel(l.settingsSectionApp),
            _SettingsCard(
              children: [
                _SettingsRow(
                  icon: AppIcons.globe,
                  title: l.settingsLanguage,
                  subtitle: localeLabel,
                  onTap: _pickLocale,
                ),
                const _CardDivider(),
                _SettingsRow(
                  icon: AppIcons.palette,
                  title: l.settingsAppearance,
                  subtitle: _themeModeLabel(l, themeMode),
                  onTap: _pickThemeMode,
                ),
              ],
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
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 0,
              children: [
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(AppConfig.privacyPolicyUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(l.settingsPrivacyPlaceholder),
                ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(AppConfig.termsOfServiceUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(l.settingsTerms),
                ),
                if (!hideInAppPlategaCheckout)
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(AppConfig.pricingUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(l.settingsPricing),
                  ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(AppConfig.supportPageUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(l.settingsSupport),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (AppConfig.authAnonymous)
              _SettingsCard(
                children: [
                  _SettingsRow(
                    icon: AppIcons.devices,
                    title: l.settingsDeviceId,
                    subtitle: _installId ?? l.settingsDeviceIdHint,
                    onTap: _installId == null ? null : _copyInstallId,
                    trailing: _installId == null
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.copy_outlined,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                  ),
                ],
              )
            else
              _SettingsCard(
                children: [
                  _LogoutRow(
                    label: l.logoutTooltip,
                    inProgress: _logoutInProgress,
                    onTap: _logoutInProgress ? null : _onLogoutPressed,
                  ),
                ],
              ),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      color:
          Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

/// Telegram-style destructive logout row at the bottom of Settings.
class _LogoutRow extends StatelessWidget {
  const _LogoutRow({
    required this.label,
    required this.inProgress,
    required this.onTap,
  });

  final String label;
  final bool inProgress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const red = AppBrand.destructive;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: inProgress
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: red,
                      ),
                    )
                  : const Center(
                      child: AppIcon(AppIcons.logout, size: 22, color: red),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            leading ??
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppBrand.oakWithOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: AppIcon(icon!, size: 20),
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else if (onTap != null) ...[
              const SizedBox(width: 8),
              const AppIcon(AppIcons.chevronRight, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

/// Monochrome Living House + check (access) / X (no access).
class _AccessStatusGlyph extends StatelessWidget {
  const _AccessStatusGlyph({required this.status});

  final AsyncValue<SubscriptionStatus> status;

  static bool _hasAccess(SubscriptionStatus s) {
    // Free cold auth: empty subscription is still Free-tier access (quota VPN).
    if (s.isEmpty) return true;
    if (s.hasActivePaid || s.isTrial || s.isAlpha) return true;
    if (s.status == 'cancelled' &&
        s.expiresAt != null &&
        s.expiresAt!.isAfter(DateTime.now())) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.onSurface;

    final bool? ok;
    final bool pending;
    if (status.isLoading) {
      ok = null;
      pending = true;
    } else if (status.hasError) {
      ok = false;
      pending = false;
    } else {
      ok = _hasAccess(status.requireValue);
      pending = false;
    }

    final badgeColor = switch (ok) {
      true => AppBrand.success,
      false => theme.colorScheme.error,
      null => theme.colorScheme.onSurfaceVariant,
    };

    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppBrand.oakWithOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SizedBox(
        width: 26,
        height: 26,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(base, BlendMode.srcIn),
                  child: Image.asset(
                    'assets/icon/mono_teremok.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) =>
                        const AppIcon(AppIcons.houseFill, size: 20),
                  ),
                ),
              ),
            ),
            if (!pending && ok != null)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.surface,
                      width: 1.5,
                    ),
                  ),
                  child: AppIcon(
                    ok ? AppIcons.checkCircleFill : AppIcons.xCircleFill,
                    size: 14,
                    color: badgeColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
