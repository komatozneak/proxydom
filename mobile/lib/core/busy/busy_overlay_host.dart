import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';
import '../widgets/app_icon.dart';
import 'busy_overlay.dart';

/// Always-mounted shell overlay. Idle = opacity 0 + ignore pointers.
///
/// Uses a dim [ColoredBox] only (no [BackdropFilter]) so dialogs / VPN surface
/// churn cannot trip InheritedElement `_dependents.isEmpty`.
class BusyOverlayHost extends ConsumerWidget {
  const BusyOverlayHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(busyOverlayProvider);
    final theme = Theme.of(context);
    final active = busy.isBusy;
    final isSuccess = busy.phase == BusyPhase.success;
    final isFailed = busy.phase == BusyPhase.failed;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !active,
        child: Opacity(
          opacity: active ? 1 : 0,
          child: ColoredBox(
            color: theme.colorScheme.surface.withValues(alpha: 0.78),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!active)
                      const SizedBox.shrink()
                    else if (isSuccess)
                      const AppIcon(
                        AppIcons.checkCircleFill,
                        size: 44,
                        color: AppBrand.success,
                      )
                    else if (isFailed)
                      const AppIcon(
                        AppIcons.warning,
                        size: 44,
                        color: AppBrand.destructive,
                      )
                    else
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    if (active &&
                        busy.title != null &&
                        busy.title!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        busy.title!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (active &&
                        busy.body != null &&
                        busy.body!.isNotEmpty &&
                        busy.phase == BusyPhase.working) ...[
                      const SizedBox(height: 8),
                      Text(
                        busy.body!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
