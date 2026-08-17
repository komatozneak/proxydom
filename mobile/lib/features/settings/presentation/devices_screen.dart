import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config.dart';
import '../../../core/api_secret_storage.dart';
import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/logout_handler.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/recovery_code_storage.dart';
import '../../session/application/identity_reconnect.dart';
import '../../session/application/session_provider.dart';
import '../application/devices_list_provider.dart';
import '../application/seat_accept_flow.dart';
import '../application/seat_invite_flow.dart';
import '../application/seat_join_code_provider.dart';

/// Account device slots — list, invite, join, revoke, leave.
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  bool _busy = false;
  bool _joinConsumeScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _consumePendingJoinCode();
  }

  /// Deep link `teremokconnect://join` lands here with a pending code.
  void _consumePendingJoinCode() {
    if (_joinConsumeScheduled) return;
    final pending = ref.read(seatJoinCodeProvider)?.trim();
    if (pending == null || pending.isEmpty) return;
    _joinConsumeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _joinConsumeScheduled = false;
      if (!mounted) return;
      final code = ref.read(seatJoinCodeProvider)?.trim();
      if (code == null || code.isEmpty) return;
      ref.read(seatJoinCodeProvider.notifier).state = null;
      runSeatAcceptFlow(context: context, ref: ref, initialCode: code);
    });
  }

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
      final snap = await AuthApi().revokeDevice(device.id);
      if (snap != null) {
        await ref.read(sessionProvider.notifier).apply(snap);
      } else {
        await ref.read(devicesListProvider.notifier).refresh();
      }
      await teardownVpnAfterIdentityChange(ref);
      if (!mounted) return;
      showTeremokSnackBar(context, l.devicesRevoked);
    } catch (_) {
      if (!mounted) return;
      showTeremokSnackBar(context, l.devicesRevokeFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(DeviceSlot device) async {
    final l = AppL10n.of(context);
    final initial = (device.deviceName?.trim().isNotEmpty == true)
        ? device.deviceName!.trim()
        : '';
    final controller = TextEditingController(text: initial);
    final saved = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l.devicesRenameTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 128,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: l.devicesRenameHint,
            ),
            onSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed.isEmpty) return;
              Navigator.of(ctx, rootNavigator: true).pop(trimmed);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
              child: Text(l.devicesCancel),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isEmpty) return;
                Navigator.of(ctx, rootNavigator: true).pop(trimmed);
              },
              child: Text(l.devicesRenameSave),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (saved == null || saved.isEmpty || !mounted) return;
    if (saved == initial) return;
    setState(() => _busy = true);
    try {
      final snap = await AuthApi().renameDevice(
        devicePk: device.id,
        deviceName: saved,
      );
      if (snap != null) {
        await ref.read(sessionProvider.notifier).apply(snap);
      } else {
        await ref.read(devicesListProvider.notifier).refresh();
      }
      if (!mounted) return;
      showTeremokSnackBar(context, l.devicesRenamed);
    } catch (_) {
      if (!mounted) return;
      showTeremokSnackBar(context, l.devicesRenameFailed);
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
      final secret = result.apiSecret?.trim();
      if (secret != null && secret.isNotEmpty) {
        await ApiSecretStorage.instance.save(secret);
      }
      final snap = result.session;
      if (snap != null) {
        await ref.read(sessionProvider.notifier).apply(snap);
      }
      await teardownVpnAfterIdentityChange(ref);
      final code = result.recoveryCode?.trim();
      if (code != null && code.isNotEmpty) {
        await RecoveryCodeStorage.instance.savePending(code);
        AppRouter.pendingRecoveryCode = code;
      }
      if (!mounted) return;
      showTeremokSnackBar(context, l.devicesLeft);
      if (code != null && code.isNotEmpty) {
        context.go('/recovery');
      } else {
        await ref.read(devicesListProvider.notifier).refresh();
      }
    } catch (_) {
      if (!mounted) return;
      showTeremokSnackBar(context, l.devicesLeaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logoutAll() async {
    final l = AppL10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(l.devicesLogoutAllTitle),
        content: Text(l.devicesLogoutAllBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: Text(l.devicesCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            child: Text(l.devicesLogoutAllConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AuthApi().logoutAll();
      await ref.read(logoutHandlerProvider).logout();
      if (!mounted) return;
      if (AppConfig.authAnonymous) {
        context.go('/gate');
      }
    } catch (_) {
      if (!mounted) return;
      showTeremokSnackBar(context, l.devicesLogoutAllFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inviteDevice() async {
    setState(() => _busy = true);
    try {
      await runSeatInviteFlow(context: context, ref: ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(devicesListProvider);

    ref.listen<String?>(seatJoinCodeProvider, (prev, next) {
      final code = next?.trim();
      if (code == null || code.isEmpty) return;
      _consumePendingJoinCode();
    });

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
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
          data: (data) => _hub(context, l, theme, data),
        ),
      ),
    );
  }

  Widget _hub(
    BuildContext context,
    AppL10n l,
    ThemeData theme,
    DeviceListResult data,
  ) {
    final current = data.devices.where((d) => d.isCurrent).toList();
    final others = data.devices.where((d) => !d.isCurrent).toList();
    final ordered = [...current, ...others];
    final currentIsOwner = current.any((d) => d.isOwner);
    final currentIsMember = current.any((d) => !d.isOwner);
    final seatsEnabled = data.maxDevices > 1;
    final showInvite = currentIsOwner && seatsEnabled;
    final showJoin = AppConfig.authAnonymous &&
        (currentIsMember ||
            (currentIsOwner && data.activeCount == 1) ||
            current.isEmpty);
    final showLeave = currentIsMember && data.activeCount > 1;
    final showLogoutAll = currentIsOwner;
    final locale = Localizations.localeOf(context).toString();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          l.devicesTitle,
          style: theme.textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l.devicesCount(data.activeCount, data.maxDevices),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l.devicesHint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        _HubCard(
          children: [
            if (ordered.isEmpty)
              _HubMessage(l.devicesEmpty)
            else
              for (var i = 0; i < ordered.length; i++) ...[
                if (i > 0) const _HubDivider(),
                _DeviceRow(
                  device: ordered[i],
                  l: l,
                  locale: locale,
                  onRename: (ordered[i].isCurrent || currentIsOwner) && !_busy
                      ? () => _rename(ordered[i])
                      : null,
                  onRevoke: !ordered[i].isCurrent && currentIsOwner && !_busy
                      ? () => _revoke(ordered[i])
                      : null,
                ),
              ],
          ],
        ),
        if (showInvite || showJoin || showLeave || showLogoutAll) ...[
          const SizedBox(height: 20),
          _HubCard(
            children: [
              if (showInvite)
                _ActionRow(
                  icon: AppIcons.plus,
                  title: l.settingsInviteDevice,
                  subtitle: l.settingsInviteDeviceHint,
                  onTap: _busy ? null : _inviteDevice,
                ),
              if (showInvite && (showJoin || showLeave || showLogoutAll))
                const _HubDivider(),
              if (showJoin)
                _ActionRow(
                  icon: AppIcons.signIn,
                  title: l.settingsAcceptSeat,
                  subtitle: l.settingsAcceptSeatHint,
                  onTap: _busy
                      ? null
                      : () => runSeatAcceptFlow(context: context, ref: ref),
                ),
              if (showJoin && (showLeave || showLogoutAll)) const _HubDivider(),
              if (showLeave)
                _ActionRow(
                  icon: AppIcons.logout,
                  title: l.devicesLeave,
                  subtitle: l.devicesLeaveHint,
                  destructive: true,
                  onTap: _busy ? null : _leave,
                ),
              if (showLeave && showLogoutAll) const _HubDivider(),
              if (showLogoutAll)
                _ActionRow(
                  icon: AppIcons.logout,
                  title: l.devicesLogoutAll,
                  subtitle: l.devicesLogoutAllHint,
                  destructive: true,
                  onTap: _busy ? null : _logoutAll,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.children});

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

class _HubDivider extends StatelessWidget {
  const _HubDivider();

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

class _HubMessage extends StatelessWidget {
  const _HubMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.l,
    required this.locale,
    required this.onRevoke,
    this.onRename,
  });

  final DeviceSlot device;
  final AppL10n l;
  final String locale;
  final VoidCallback? onRevoke;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = (device.deviceName?.trim().isNotEmpty == true)
        ? device.deviceName!.trim()
        : l.devicesUntitled;
    final created = DateFormat.yMMMd(locale).format(device.createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
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
                  l.devicesCreated(created),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onRename != null)
            IconButton(
              tooltip: l.devicesRename,
              onPressed: onRename,
              icon: AppIcon(
                AppIcons.pencil,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (device.isCurrent)
            Text(
              l.devicesCurrentDevice,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (onRevoke != null)
            IconButton(
              tooltip: l.devicesRevoke,
              onPressed: onRevoke,
              icon: AppIcon(
                AppIcons.xCircle,
                size: 22,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = destructive ? AppBrand.destructive : theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: destructive
                    ? AppBrand.destructive.withValues(alpha: 0.08)
                    : AppBrand.oakWithOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: AppIcon(icon, size: 20, color: color),
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
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
