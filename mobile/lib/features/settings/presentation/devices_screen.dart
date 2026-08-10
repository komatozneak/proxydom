import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/recovery_code_storage.dart';
import '../application/devices_list_provider.dart';

/// Account device slots — list, revoke other installs, leave this install.
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  bool _busy = false;

  Future<void> _revoke(DeviceSlot device) async {
    final l = AppL10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(l.devicesRevokeTitle),
        content: Text(l.devicesRevokeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: Text(l.devicesCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            child: Text(l.devicesRevokeConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AuthApi().revokeDevice(device.id);
      await ref.read(devicesListProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.devicesRevoked)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.devicesRevokeFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final l = AppL10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(l.devicesLeaveTitle),
        content: Text(l.devicesLeaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: Text(l.devicesCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            child: Text(l.devicesLeaveConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await AuthApi().leaveDevice();
      await ref.read(authProvider.notifier).authenticated(
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
          );
      final code = result.recoveryCode?.trim();
      if (code != null && code.isNotEmpty) {
        await RecoveryCodeStorage.instance.savePending(code);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.devicesLeft)),
      );
      if (code != null && code.isNotEmpty) {
        context.go('/recovery');
      } else {
        await ref.read(devicesListProvider.notifier).refresh();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.devicesLeaveFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(devicesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.devicesTitle),
        leading: IconButton(
          tooltip: l.navBack,
          icon: AppIcon(
            AppIcons.backBold,
            size: 28,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/settings');
            }
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(devicesListProvider.notifier).refresh(),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Text(l.devicesLoadError),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => ref.read(devicesListProvider.notifier).refresh(),
                child: Text(l.homeRetry),
              ),
            ],
          ),
          data: (data) {
            final hasCurrent = data.devices.any((d) => d.isCurrent);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                Text(
                  l.devicesCount(data.activeCount, data.maxDevices),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l.devicesHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                if (data.devices.isEmpty)
                  Text(l.devicesEmpty)
                else
                  ...data.devices.map((d) {
                    final title = (d.deviceName?.trim().isNotEmpty == true)
                        ? d.deviceName!.trim()
                        : l.devicesUntitled;
                    final platform = d.platform?.trim();
                    final seen = d.lastSeenAt != null
                        ? DateFormat.yMMMd().add_Hm().format(d.lastSeenAt!)
                        : null;
                    final subtitle = [
                      if (d.isCurrent) l.devicesThisDevice,
                      if (platform != null && platform.isNotEmpty) platform,
                      if (seen != null) seen,
                    ].join(' · ');
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: AppIcon(
                          d.isCurrent ? AppIcons.phone : AppIcons.devices,
                          color: d.isCurrent
                              ? AppBrand.secondary
                              : theme.colorScheme.onSurface,
                        ),
                        title: Text(title),
                        subtitle: subtitle.isEmpty ? null : Text(subtitle),
                        trailing: d.isCurrent
                            ? null
                            : TextButton(
                                onPressed: _busy ? null : () => _revoke(d),
                                child: Text(l.devicesRevoke),
                              ),
                      ),
                    );
                  }),
                if (hasCurrent && data.activeCount > 1) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : _leave,
                    child: Text(l.devicesLeave),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
