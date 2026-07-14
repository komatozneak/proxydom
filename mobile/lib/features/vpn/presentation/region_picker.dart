import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../data/node_display.dart';
import '../data/vpn_controller.dart';
import '../data/vpn_node.dart';

/// Bottom sheet: auto-select + friendly region list (oak+moss, reference-inspired).
Future<void> showRegionPicker(BuildContext context, WidgetRef ref) async {
  final l = AppL10n.of(context);
  final nodesRepo = ref.read(vpnNodesRepositoryProvider);
  List<VpnNode> nodes;
  String? selectedId;
  try {
    nodes = await nodesRepo.listNodes();
    selectedId = await nodesRepo.getSelectedNodeId();
  } catch (e) {
    if (context.mounted) {
      final raw = e.toString();
      final looksLikeAbort = raw.contains('connection abort') ||
          raw.contains('Software caused connection abort') ||
          raw.contains('HttpException');
      final lockdown = looksLikeAbort
          ? await VpnController.instance.isLockdownEnabled()
          : false;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (looksLikeAbort || lockdown)
                ? l.regionLoadErrorAbort
                : l.regionLoadError(raw),
          ),
        ),
      );
    }
    return;
  }

  if (!context.mounted) return;
  if (nodes.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.regionEmpty)),
    );
    return;
  }

  final online = nodes.where((n) => n.isConnected || n.isDefault).toList();
  selectedId ??= kRegionAutoId;
  if (selectedId != kRegionAutoId &&
      !nodes.any((n) => n.id == selectedId)) {
    selectedId = kRegionAutoId;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (ctx, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(
                  l.regionTitle,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  l.regionSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                _RegionTile(
                  selected: selectedId == kRegionAutoId,
                  leading: CircleAvatar(
                    backgroundColor: AppBrand.secondary.withOpacity(0.2),
                    child: const AppIcon(AppIcons.servers, size: 22),
                  ),
                  title: l.regionAutoTitle,
                  subtitle: l.regionAutoSubtitle,
                  trailingBadge: l.regionSelected,
                  showBadge: selectedId == kRegionAutoId,
                  onTap: () => _pick(ctx, ref, kRegionAutoId, l.regionAutoTitle),
                ),
                const SizedBox(height: 12),
                Text(
                  l.regionSectionServers,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < nodes.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Builder(
                      builder: (_) {
                        final node = nodes[i];
                        if (node.isDefault) {
                          return const SizedBox.shrink();
                        }
                        final locale = Localizations.localeOf(ctx).languageCode;
                        final place = placeForNode(node, index: i);
                        final enabled = node.isConnected || node.isDefault;
                        final selected = selectedId == node.id;
                        return _RegionTile(
                          selected: selected,
                          enabled: enabled,
                          leading: CircleAvatar(
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            child: Text(
                              place.flag,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                          title: place.displayTitle(locale),
                          subtitle:
                              '${place.displaySubtitle(locale)} · ${enabled ? l.regionOnline : l.regionOffline}',
                          trailingBadge: enabled ? l.regionFree : l.regionOffline,
                          showBadge: selected,
                          signalGood: enabled,
                          onTap: enabled
                              ? () => _pick(
                                    ctx,
                                    ref,
                                    node.id,
                                    place.displayTitle(locale),
                                  )
                              : null,
                        );
                      },
                    ),
                  ),
                if (online.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l.regionNoneOnline,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}

Future<void> _pick(
  BuildContext ctx,
  WidgetRef ref,
  String id,
  String toastLabel,
) async {
  Navigator.of(ctx).pop();
  final l = AppL10n.of(ctx);
  try {
    await ref.read(vpnProvider.notifier).selectNode(id);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l.regionChanged(toastLabel))),
      );
    }
  } catch (e) {
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l.regionChangeFailed(e.toString()))),
      );
    }
  }
}

class _RegionTile extends StatelessWidget {
  const _RegionTile({
    required this.selected,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailingBadge,
    required this.showBadge,
    this.enabled = true,
    this.signalGood = true,
    this.onTap,
  });

  final bool selected;
  final bool enabled;
  final Widget leading;
  final String title;
  final String subtitle;
  final String trailingBadge;
  final bool showBadge;
  final bool signalGood;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = selected
        ? Border.all(color: AppBrand.accent, width: 1.5)
        : Border.all(color: theme.colorScheme.outlineVariant);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(
        enabled ? 0.35 : 0.15,
      ),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: border,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: enabled
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.outline,
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
              if (showBadge)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppBrand.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    trailingBadge,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppBrand.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    trailingBadge,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              const SizedBox(width: 8),
              _SignalBars(good: signalGood && enabled),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.good});

  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? AppBrand.success : AppBrand.warning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final h = 6.0 + i * 3;
        return Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Container(
            width: 4,
            height: h,
            decoration: BoxDecoration(
              color: i < (good ? 4 : 2) ? color : color.withOpacity(0.25),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      }),
    );
  }
}
