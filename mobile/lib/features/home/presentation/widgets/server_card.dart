import 'package:flutter/material.dart';

import '../../../../core/widgets/app_icon.dart';
import '../../../../l10n/app_localizations.dart';

/// Tappable server shortcut (Variant 4) — full-width outlined card, min 56dp.
class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.flagEmoji,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String flagEmoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppL10n.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Text(flagEmoji, style: const TextStyle(fontSize: 22)),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              subtitle.isEmpty ? l.homeStatServer : subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: AppIcon(
              AppIcons.chevronRight,
              size: 22,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
