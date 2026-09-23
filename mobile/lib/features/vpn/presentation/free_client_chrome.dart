import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';

/// Paste and QR, the same size on Home, Servers, and Add.
class FreeClientActionBar extends StatelessWidget {
  const FreeClientActionBar({
    super.key,
    required this.onPaste,
    required this.onScan,
  });

  final VoidCallback onPaste;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppBrand.radiusPill),
    );
    const pad = EdgeInsets.symmetric(horizontal: 12, vertical: 14);
    return Row(
      children: [
        Expanded(
          child: _action(
            onPressed: onPaste,
            icon: AppIcons.clipboard,
            label: l.freePaste,
            background: AppBrand.secondary,
            foreground: AppBrand.surfaceElevatedLight,
            shape: shape,
            pad: pad,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _action(
            onPressed: onScan,
            icon: AppIcons.qrCode,
            label: l.freeQr,
            background: AppBrand.paperMargin,
            foreground: AppBrand.inkLight,
            shape: shape,
            pad: pad,
          ),
        ),
      ],
    );
  }

  Widget _action({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color background,
    required Color foreground,
    required OutlinedBorder shape,
    required EdgeInsets pad,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: AppIcon(icon, size: 18, color: foreground),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: FilledButton.styleFrom(
        padding: pad,
        shape: shape,
        backgroundColor: background,
        foregroundColor: foreground,
      ),
    );
  }
}

class FreeClientEmptyState extends StatelessWidget {
  const FreeClientEmptyState({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          AppIcons.folder,
          size: compact ? 36 : 48,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        SizedBox(height: compact ? 8 : 12),
        Text(
          l.freeEmptyTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l.freeEmptyBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Structured connection facts. Not a paragraph under the house.
class ConnectionStatusPanel extends StatelessWidget {
  const ConnectionStatusPanel({
    super.key,
    required this.status,
    required this.profile,
    required this.protocol,
    required this.accent,
    this.uptime,
  });

  final String status;
  final String profile;
  final String protocol;
  final Color accent;
  final String? uptime;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        children: [
          _row(theme, l.freeStatus, status, emphasize: true, valueColor: accent),
          _row(theme, l.freeProfile, profile),
          _row(theme, l.freeProtocol, protocol),
          if (uptime != null)
            _row(theme, l.freeUptime, uptime!, valueColor: accent),
        ],
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    String label,
    String value, {
    bool emphasize = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImportedProfileCard extends StatelessWidget {
  const ImportedProfileCard({
    super.key,
    required this.name,
    required this.scheme,
    required this.endpoint,
    required this.selected,
    this.connected = false,
    this.onTap,
    this.onDelete,
  });

  final String name;
  final String scheme;
  final String endpoint;
  final bool selected;
  final bool connected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppL10n.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          endpoint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Text(
            scheme.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (connected)
              Icon(AppIcons.checkCircleFill, color: AppBrand.success, size: 18),
            if (onDelete != null)
              IconButton(
                tooltip: l.freeDelete,
                onPressed: onDelete,
                icon: const AppIcon(AppIcons.trash, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}
