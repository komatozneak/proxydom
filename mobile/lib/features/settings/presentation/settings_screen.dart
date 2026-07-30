import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/application/logout_handler.dart';
import '../../beta/application/beta_usage_tracker.dart';
import '../../home/application/vpn_provider.dart';
import '../application/locale_provider.dart';
import '../application/subscription_status_provider.dart';
import '../application/theme_mode_provider.dart';
import '../data/access_status_copy.dart';
import '../data/auto_reconnect_prefs.dart';
import '../data/subscription_status.dart';
import '../data/vpn_notification_prefs.dart';
import 'kill_switch_settings_tile.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _sending = false;
  bool _logoutInProgress = false;
  bool? _notifEnabled;
  bool _notifLoading = false;
  bool? _autoReconnect;
  bool _autoReconnectLoading = false;
  String _versionLabel = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final futures = <Future<void>>[
      _loadAutoReconnect(),
      _loadVersion(),
    ];
    if (VpnNotificationPrefs.isSupported) {
      futures.add(_loadNotif());
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
              return l.settingsAccessActiveUntil(_formatAccessDate(s.expiresAt!));
            }
            return l.settingsAccessBetaSubtitle;
          case AccessCopyKind.cancelled:
            return l.settingsAccessCancelledSubtitle;
          case AccessCopyKind.closedBeta:
            if (s.expiresAt != null) {
              return l.settingsAccessActiveUntil(_formatAccessDate(s.expiresAt!));
            }
            return l.settingsAccessBetaSubtitle;
          case AccessCopyKind.none:
            return l.settingsAccessNoneSubtitle;
          case AccessCopyKind.generic:
            if (s.status == 'expired' && s.expiresAt != null) {
              return l.settingsAccessActiveUntil(_formatAccessDate(s.expiresAt!));
            }
            return l.settingsAccessNoneSubtitle;
        }
      },
      loading: () => '?',
      error: (_, __) => l.settingsSubscriptionLoadError,
    );
  }

  Future<void> _sendReport() async {
    final l = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsSendReport),
        content: Text(l.settingsSendReportHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.settingsSendReportConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final auth = ref.read(authProvider).valueOrNull;
      if (auth is! AuthStateAuthenticated) {
        throw StateError('not authenticated');
      }
      final access = auth.accessToken;

      final service = DiagnosticsService();
      final report = await service.buildReport(
        authState: auth,
        vpnUi: ref.read(vpnProvider),
        cachedConfig: ref.read(vpnProvider.notifier).config,
      );
      await service.submit(accessToken: access, report: report);
      ref.read(betaUsageTrackerProvider).recordDiagnosticReportSent();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsReportSent)),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final message = switch (e.response?.statusCode) {
        401 || 403 => l.settingsReportUnauthorized,
        _ when e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.sendTimeout ||
                e.type == DioExceptionType.receiveTimeout ||
                e.type == DioExceptionType.connectionError =>
          l.settingsReportNetworkError,
        _ => l.settingsReportFailed,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsReportFailed)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l.logoutWarning}: ${result.message}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
    // GoRouter redirects to /login via refreshListenable.
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
    final current =
        ref.read(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final chosen = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in ThemeMode.values)
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
    final current = ref.read(localeProvider).valueOrNull ??
        Localizations.localeOf(context);
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
    final notifOn = _notifEnabled ?? true;
    final autoOn = _autoReconnect ?? true;
    final subAsync = ref.watch(subscriptionStatusProvider);
    final themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final locale =
        ref.watch(localeProvider).valueOrNull ?? Localizations.localeOf(context);
    final localeLabel = _localeLabel(l, locale);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(l.settingsTitle),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _SectionLabel(l.settingsSectionAccount),
          _SettingsCard(
            children: [
              _SettingsRow(
                leading: _AccessStatusGlyph(status: subAsync),
                title: _accessTitle(l, subAsync),
                subtitle: _accessSubtitle(l, subAsync),
                trailing: subAsync.when(
                  data: (_) => null,
                  loading: () => const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => TextButton(
                    onPressed: () =>
                        ref.read(subscriptionStatusProvider.notifier).refresh(),
                    child: Text(l.homeRetry),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel(l.settingsSectionConnection),
          _SettingsCard(
            children: [
              _SettingsRow(
                icon: AppIcons.refresh,
                title: l.settingsAutoReconnect,
                subtitle: l.settingsAutoReconnectHint,
                trailing: Switch.adaptive(
                  value: autoOn,
                  onChanged: _autoReconnectLoading || _autoReconnect == null
                      ? null
                      : _onAutoReconnectChanged,
                ),
              ),
              const _CardDivider(),
              _SettingsRow(
                icon: AppIcons.sliders,
                title: l.settingsSplitTunnel,
                subtitle: l.settingsSplitTunnelHint,
                onTap: () => context.push('/settings/split-tunnel'),
              ),
              const _CardDivider(),
              const KillSwitchSettingsTile(),
            ],
          ),
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
                icon: AppIcons.moon,
                title: l.settingsDarkTheme,
                subtitle: _themeModeLabel(l, themeMode),
                onTap: _pickThemeMode,
              ),
              if (showNotif) ...[
                const _CardDivider(),
                _SettingsRow(
                  icon: AppIcons.notifications,
                  title: l.settingsVpnNotificationTitle,
                  subtitle: l.settingsVpnNotificationHint,
                  trailing: Switch.adaptive(
                    value: notifOn,
                    onChanged: _notifLoading || _notifEnabled == null
                        ? null
                        : _onNotifChanged,
                  ),
                ),
              ],
              const _CardDivider(),
              _SettingsRow(
                icon: AppIcons.bug,
                title: l.settingsSendReport,
                subtitle: l.settingsSendReportHint,
                trailing: _sending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const AppIcon(AppIcons.chevronRight, size: 18),
                onTap: _sending ? null : _sendReport,
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
          TextButton(
            onPressed: () {
              // Placeholder link ? real policy URL later.
              launchUrl(
                Uri.parse('https://teremokconnect.online'),
                mode: LaunchMode.externalApplication,
              );
            },
            child: Text(l.settingsPrivacyPlaceholder),
          ),
          const SizedBox(height: 12),
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
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
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
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(18),
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
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
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
