import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../l10n/app_localizations.dart';

/// Read-only server pill (active hop label + optional RTT). No location picker.
class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.flagEmoji,
    this.pingMs,
  });

  final String title;
  final String subtitle;
  final String flagEmoji;

  /// Live urltest RTT when connected; null when unknown / disconnected.
  final int? pingMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppL10n.of(context);
    final elevated = theme.colorScheme.surfaceContainerHighest;
    final line = theme.colorScheme.outline;
    final ping = pingMs;
    final trailing = ping != null ? '${ping} ms' : null;

    return Material(
      color: elevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusPill),
        side: BorderSide(color: line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppBrand.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(flagEmoji, style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.isEmpty ? l.homeStatServer : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                Text(
                  trailing,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
