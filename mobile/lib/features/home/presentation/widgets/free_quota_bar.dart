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
    this.teaser,
    this.ctaLabel,
    this.onTap,
  });

  /// 0 = empty, 1 = full Free cap.
  final double remainingFraction;
  final String title;
  final String amountLabel;
  final String exhaustedLabel;

  /// Premium upsell strip under the track (Home only).
  final String? teaser;
  final String? ctaLabel;
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
    final showCurtain = widget.teaser != null && widget.teaser!.isNotEmpty;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusPill),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
                      _QuotaTrack(fraction: value),
                    ],
                  );
                },
              ),
            ),
            if (showCurtain)
              ColoredBox(
                color: AppBrand.livingHouse,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.teaser!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppBrand.accentOnDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.ctaLabel ?? '',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppBrand.accentOnDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Visible HP gutter on the white quota card (`surfaceContainerHighest`).
const Key kFreeQuotaTrackKey = Key('free_quota_hp_track');

/// Track height — 10px on `surface` used to vanish into the cream card.
const double kFreeQuotaTrackHeight = 16;

class _QuotaTrack extends StatelessWidget {
  const _QuotaTrack({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exhausted = fraction <= 0;
    final card = theme.colorScheme.surfaceContainerHighest;
    // Cream page `surface` (#F4F4F5) is the card's neighbour — use a muted
    // wash so the empty gutter reads as a trough, not a missing widget.
    final gutter = Color.alphaBlend(
      theme.colorScheme.outline.withValues(alpha: 0.28),
      card,
    );
    return SizedBox(
      key: kFreeQuotaTrackKey,
      height: kFreeQuotaTrackHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: gutter,
          borderRadius: BorderRadius.circular(AppBrand.radiusNavPill),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.72),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(1.5),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Exhausted renders as a full muted bar + «Трафик закончился».
              final width = exhausted
                  ? constraints.maxWidth
                  : (constraints.maxWidth * fraction).clamp(
                      0.0,
                      constraints.maxWidth,
                    );
              // Soft drain gradient: the right tip carries the current
              // health tone, the left stays one step healthier (moss →
              // mustard → soft red), so the bar never flashes harsh red.
              final tip = freeQuotaBarColor(fraction);
              final trail = freeQuotaBarColor(
                (fraction + 0.35).clamp(0.0, 1.0),
              );
              return Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: width,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: exhausted ? AppBrand.quotaDepleted : null,
                      gradient: exhausted
                          ? null
                          : LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [trail, tip],
                            ),
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
