import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../data/free_quota_meter.dart';

/// Game-style remaining-traffic bar: fill + colour tween together.
class FreeQuotaBar extends StatefulWidget {
  const FreeQuotaBar({
    super.key,
    required this.remainingFraction,
    required this.title,
    required this.amountLabel,
    required this.exhaustedLabel,
    this.onTap,
  });

  /// 0 = empty, 1 = full Free cap.
  final double remainingFraction;
  final String title;
  final String amountLabel;
  final String exhaustedLabel;
  final VoidCallback? onTap;

  @override
  State<FreeQuotaBar> createState() => _FreeQuotaBarState();
}

class _FreeQuotaBarState extends State<FreeQuotaBar> {
  late double _from;
  late double _to;

  @override
  void initState() {
    super.initState();
    _to = widget.remainingFraction.clamp(0.0, 1.0);
    _from = _to;
  }

  @override
  void didUpdateWidget(covariant FreeQuotaBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.remainingFraction.clamp(0.0, 1.0);
    if (next != _to) {
      _from = _to;
      _to = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exhausted = _to <= 0;
    final caption = exhausted ? widget.exhaustedLabel : widget.amountLabel;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusPill),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(AppBrand.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: TweenAnimationBuilder<double>(
            duration: _from == _to
                ? Duration.zero
                : const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(begin: _from, end: _to),
            key: ValueKey<double>(_to),
            builder: (context, value, _) {
              final fill = freeQuotaBarColor(value);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        caption,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: exhausted
                              ? theme.colorScheme.onSurfaceVariant
                              : fill,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _QuotaTrack(fraction: value, color: fill),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _QuotaTrack extends StatelessWidget {
  const _QuotaTrack({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 10,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppBrand.radiusNavPill),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1.5),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth * fraction).clamp(
                0.0,
                constraints.maxWidth,
              );
              return Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: width,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(
                        AppBrand.radiusNavPill,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
