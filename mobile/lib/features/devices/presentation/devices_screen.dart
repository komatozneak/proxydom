import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/install_id_storage.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../../vpn/data/vpn_config.dart';
import '../data/devices_repository.dart';

final devicesRepositoryProvider = Provider<DevicesRepository>(
  (ref) => DevicesRepository(),
);

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  DeviceListResult? _list;
  Object? _error;
  bool _loading = true;
  int? _revokingId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final installId = await InstallIdStorage.instance.getOrCreate();
      final result = await ref
          .read(devicesRepositoryProvider)
          .listDevices(currentDeviceId: installId);
      if (!mounted) return;
      setState(() {
        _list = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _revoke(DeviceSlot slot) async {
    final l = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.devicesRevokeTitle),
        content: Text(l.devicesRevokeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.devicesCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.devicesRevokeConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _revokingId = slot.id);
    try {
      await ref.read(devicesRepositoryProvider).revokeDevice(slot.id);
      if (slot.isCurrent) {
        VpnConfigCache.instance.clear();
        try {
          await ref.read(vpnProvider.notifier).disconnect();
        } catch (_) {
          // Best-effort; slot already revoked server-side.
        }
      }
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.devicesRevoked)),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.devicesRevokeFailed)),
      );
      // ignore: avoid_print
      print('[Devices] revoke failed: $e');
    } finally {
      if (mounted) setState(() => _revokingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final list = _list;

    return Scaffold(
      appBar: AppBar(title: Text(l.devicesTitle)),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (list != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  l.devicesCount(list.activeCount, list.maxDevices),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            Text(
              l.devicesHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  children: [
                    Text(l.devicesLoadError),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _reload, child: Text(l.homeRetry)),
                  ],
                ),
              )
            else if (list == null || list.devices.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Text(
                  l.devicesEmpty,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              ...list.devices.map((slot) {
                final title = slot.deviceName?.isNotEmpty == true
                    ? slot.deviceName!
                    : (slot.platform ?? l.devicesUntitled);
                final when = slot.lastSeenAt ?? slot.createdAt;
                final whenLabel = DateFormat.yMMMd().add_Hm().format(
                      when.toLocal(),
                    );
                final subtitle = [
                  if (slot.platform != null) slot.platform!,
                  whenLabel,
                  if (slot.isCurrent) l.devicesThisDevice,
                ].join(' · ');
                final busy = _revokingId == slot.id;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: scheme.surfaceContainerHighest,
                  child: ListTile(
                    leading: Icon(
                      AppIcons.devices,
                      color: scheme.primary,
                    ),
                    title: Text(title),
                    subtitle: Text(subtitle),
                    trailing: busy
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: () => _revoke(slot),
                            child: Text(l.devicesRevoke),
                          ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
