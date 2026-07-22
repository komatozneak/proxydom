import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../home/application/vpn_provider.dart';
import '../data/vpn_notification_prefs.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _sending = false;
  bool? _notifEnabled;
  bool _notifLoading = false;

  @override
  void initState() {
    super.initState();
    if (VpnNotificationPrefs.isSupported) {
      _loadNotif();
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
    if (!mounted) return;
    setState(() => _notifLoading = false);
  }

  Future<void> _sendReport() async {
    final l = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsReportSent)),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsReportFailed('${e.message}'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsReportFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final showNotif = VpnNotificationPrefs.isSupported;
    final notifOn = _notifEnabled ?? true;

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        children: [
          if (showNotif)
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: Text(l.settingsVpnNotificationTitle),
              subtitle: Text(
                l.settingsVpnNotificationHint,
                style: theme.textTheme.bodySmall,
              ),
              value: notifOn,
              onChanged: _notifLoading || _notifEnabled == null
                  ? null
                  : _onNotifChanged,
            ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(l.settingsSendReport),
            subtitle: Text(
              l.settingsSendReportHint,
              style: theme.textTheme.bodySmall,
            ),
            trailing: _sending
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _sending ? null : _sendReport,
          ),
        ],
      ),
    );
  }
}
