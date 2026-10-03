import 'package:flutter/material.dart';

import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';

/// Paste, and on the phone a matching QR. Windows has no camera and no QR.
///
/// [onRefresh] reloads saved subscription documents. On the phone it is a
/// small circular-arrow control beside QR. On Windows it is a labeled button
/// beside Paste.
class FreeClientActionBar extends StatelessWidget {
  const FreeClientActionBar({
    super.key,
    required this.onPaste,
    required this.onScan,
    this.onRefresh,
  });

  final VoidCallback onPaste;
  final VoidCallback onScan;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppBrand.radiusPill),
    );
    const pad = EdgeInsets.symmetric(horizontal: 12, vertical: 14);
    const barHeight = 52.0;
    final paste = _action(
      onPressed: onPaste,
      icon: AppIcons.clipboard,
      label: l.freePaste,
      background: AppBrand.secondary,
      foreground: AppBrand.surfaceElevatedLight,
      shape: shape,
      pad: pad,
      height: barHeight,
    );
    final refresh = onRefresh;
    if (windowsDesktop) {
      if (refresh == null) {
        return SizedBox(height: barHeight, width: double.infinity, child: paste);
      }
      return SizedBox(
        height: barHeight,
        child: Row(
          children: [
            Expanded(child: paste),
            const SizedBox(width: 8),
            Expanded(
              child: _action(
                onPressed: refresh,
                icon: AppIcons.refresh,
                label: l.freeRefresh,
                background: AppBrand.paperMargin,
                foreground: AppBrand.inkLight,
                shape: shape,
                pad: pad,
                height: barHeight,
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: barHeight,
      child: Row(
        children: [
          Expanded(child: paste),
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
              height: barHeight,
            ),
          ),
          if (refresh != null) ...[
            const SizedBox(width: 8),
            _PhoneRefreshButton(onPressed: refresh, tooltip: l.freeRefresh),
          ],
        ],
      ),
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
    required double height,
  }) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: AppIcon(icon, size: 18, color: foreground),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: FilledButton.styleFrom(
          padding: pad,
          minimumSize: Size(double.infinity, height),
          fixedSize: Size.fromHeight(height),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: shape,
          backgroundColor: background,
          foregroundColor: foreground,
        ),
      ),
    );
  }
}

/// Phone-only reload. No caption: the circular arrows are the label.
class _PhoneRefreshButton extends StatelessWidget {
  const _PhoneRefreshButton({
    required this.onPressed,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: AppBrand.paperMargin,
          foregroundColor: AppBrand.inkLight,
          shape: const CircleBorder(),
        ),
        icon: const AppIcon(AppIcons.refresh, size: 20, color: AppBrand.inkLight),
      ),
    );
  }
}

class FreeClientEmptyState extends StatelessWidget {
  const FreeClientEmptyState({super.key, this.compact = false});

  final bool compact;

  /// The DOM mark, the same plate the launcher icon, the bottom nav and the
  /// download card carry — not a generic folder glyph. It is self-contained, so
  /// it needs no tint per theme, and it must not be ColorFiltered: that crushes
  /// the DOM cutout.
  static const _markAsset = 'assets/icon/logo_mark_nav.png';

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          _markAsset,
          width: compact ? 40 : 56,
          height: compact ? 40 : 56,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          // The title and body below already name what is missing.
          excludeFromSemantics: true,
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
          windowsDesktop ? l.freeAddHint : l.freeEmptyBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Structured connection facts with notebook-style dots and ruled rows.
class ConnectionStatusPanel extends StatelessWidget {
  const ConnectionStatusPanel({
    super.key,
    required this.status,
    required this.profile,
    required this.traffic,
    required this.accent,
    this.uptime,
    this.trafficColor,
  });

  final String status;
  final String profile;
  final String traffic;
  final Color accent;

  /// How long this connection has been up. Absent when there is no session.
  final String? uptime;
  final Color? trafficColor;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final rule = AppBrand.paperMargin.withValues(alpha: dark ? 0.55 : 0.72);
    final mute = theme.colorScheme.onSurfaceVariant;
    final sessionColor = dark ? AppBrand.accentOnDark : AppBrand.inkLight;

    final rows = <({
      String label,
      String value,
      bool underline,
      bool emphasize,
      Color? valueColor,
    })>[
      (
        label: l.freeStatus,
        value: status,
        underline: true,
        emphasize: true,
        valueColor: accent,
      ),
      (
        label: l.freeProfile,
        value: profile,
        underline: true,
        emphasize: false,
        valueColor: null,
      ),
      (
        label: l.freeTrafficLeft,
        value: traffic,
        underline: uptime != null,
        emphasize: false,
        valueColor: trafficColor,
      ),
      if (uptime != null)
        (
          label: l.freeUptime,
          value: uptime!,
          underline: false,
          emphasize: false,
          valueColor: sessionColor,
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (final row in rows)
                    _NotebookHalf(
                      text: row.label,
                      align: TextAlign.start,
                      underline: row.underline,
                      rule: rule,
                      leadingDot: true,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: mute,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              width: 1.2,
              margin: const EdgeInsets.symmetric(vertical: 2),
              color: rule,
            ),
            Expanded(
              child: Column(
                children: [
                  for (final row in rows)
                    _NotebookHalf(
                      text: row.value,
                      align: TextAlign.end,
                      underline: row.underline,
                      rule: rule,
                      trailingDot: true,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight:
                            row.emphasize ? FontWeight.w800 : FontWeight.w700,
                        color: row.valueColor,
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

class _NotebookHalf extends StatelessWidget {
  const _NotebookHalf({
    required this.text,
    required this.align,
    required this.underline,
    required this.rule,
    required this.style,
    this.leadingDot = false,
    this.trailingDot = false,
  });

  final String text;
  final TextAlign align;
  final bool underline;
  final Color rule;
  final TextStyle? style;
  final bool leadingDot;
  final bool trailingDot;

  @override
  Widget build(BuildContext context) {
    final mute = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: underline
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: rule, width: 1.2),
              ),
            )
          : null,
      child: Row(
        children: [
          if (leadingDot) ...[
            _NotebookDot(color: mute),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text,
              textAlign: align,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (trailingDot) ...[
            const SizedBox(width: 6),
            _NotebookDot(color: mute),
          ],
        ],
      ),
    );
  }
}

class _NotebookDot extends StatelessWidget {
  const _NotebookDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        shape: BoxShape.circle,
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
    this.dialable = true,
    this.onTap,
    this.onDelete,
  });

  final String name;
  final String scheme;
  final String endpoint;
  final bool selected;
  final bool connected;
  final bool dialable;
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
          dialable ? endpoint : l.freeSchemeParked,
          maxLines: 2,
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
              const Icon(AppIcons.checkCircleFill, color: AppBrand.success, size: 18),
            if (onDelete != null)
              SheetTintTrashButton(
                tooltip: l.freeDelete,
                onPressed: onDelete!,
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks before a server or a whole list is removed.
Future<bool> confirmImportedDelete(
  BuildContext context, {
  required bool catalog,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l = AppL10n.of(dialogContext);
      return AlertDialog(
        title: Text(
          catalog ? l.freeDeleteCatalogTitle : l.freeDeleteServerTitle,
        ),
        content: Text(
          catalog ? l.freeDeleteCatalogBody : l.freeDeleteServerBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.freeDelete),
          ),
        ],
      );
    },
  );
  return ok == true;
}

/// Trash sits on a patch the color of the notebook sheet.
class SheetTintTrashButton extends StatelessWidget {
  const SheetTintTrashButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? AppBrand.paperDark : AppBrand.paperLight,
      borderRadius: BorderRadius.circular(12),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: const AppIcon(AppIcons.trash, size: 20),
      ),
    );
  }
}
