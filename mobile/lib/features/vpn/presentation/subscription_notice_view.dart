import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../data/subscription_notice.dart';

const kSubscriptionNoticeFrameKey =
    ValueKey<String>('subscription-notice-frame');
const kSubscriptionNoticePlaneKey =
    ValueKey<String>('subscription-notice-plane');
const kCatalogRefreshBandKey = ValueKey<String>('catalog-refresh-band');
const kCatalogRefreshSlotKey = ValueKey<String>('catalog-refresh-slot');
const kCatalogPlaneSlotKey = ValueKey<String>('catalog-plane-slot');
const kCatalogTrashFillKey = ValueKey<String>('catalog-trash-fill');

/// Square action cell on the profile card. Share, refresh, and trash match.
const double catalogActionExtent = 52;

/// Teeth on the tear-off edge under the Telegram plane. Three, as on the sketch.
const int catalogStampDiamonds = 3;

/// Trash cell. The same ink as the notebook margin, washed so the icon stays readable.
Color catalogTrashFill(Color surface, {required bool dark}) {
  return Color.alphaBlend(
    AppBrand.paperMargin.withValues(alpha: dark ? 0.58 : 0.55),
    surface,
  );
}

/// Profile title row. Refresh and the Telegram plane share one sky column.
/// The trash cell uses the margin ink. Share stays an unfilled icon.
class CatalogProfileChrome extends StatelessWidget {
  const CatalogProfileChrome({
    super.key,
    required this.title,
    required this.share,
    required this.trash,
    required this.band,
    required this.trashFill,
    required this.seamColor,
    this.refresh,
    this.plane,
    this.notice,
  });

  final Widget title;
  final Widget share;
  final Widget trash;
  final Color band;
  final Color trashFill;
  final Color seamColor;
  final Widget? refresh;
  final Widget? plane;
  final Widget? notice;

  Widget _seam() => SizedBox(
        width: 1,
        height: catalogActionExtent,
        child: ColoredBox(color: seamColor),
      );

  Widget _slot(Widget child, {Key? key}) => SizedBox(
        key: key,
        width: catalogActionExtent,
        height: catalogActionExtent,
        child: child,
      );

  /// Refresh cell, and when the plane is present, the tear-off stamp under it.
  Widget _refreshBand(Widget refreshButton, Widget? planeButton) {
    final slots = Column(
      children: [
        _slot(refreshButton, key: kCatalogRefreshSlotKey),
        if (planeButton != null) _slot(planeButton, key: kCatalogPlaneSlotKey),
      ],
    );
    if (planeButton == null) {
      return ColoredBox(
        key: kCatalogRefreshBandKey,
        color: band,
        child: slots,
      );
    }
    return CatalogStampBand(
      key: kCatalogRefreshBandKey,
      color: band,
      lineColor: seamColor,
      bodyHeight: catalogActionExtent * 2,
      child: slots,
    );
  }

  @override
  Widget build(BuildContext context) {
    final refreshButton = refresh;
    final planeButton = plane;
    final body = notice;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: catalogActionExtent,
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16, right: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: title,
                        ),
                      ),
                    ),
                    _seam(),
                    _slot(share),
                    if (refreshButton != null && planeButton == null) _seam(),
                  ],
                ),
              ),
              if (body != null) body,
            ],
          ),
        ),
        if (refreshButton != null)
          _refreshBand(refreshButton, planeButton),
        if (planeButton == null) _seam(),
        ColoredBox(
          key: kCatalogTrashFillKey,
          color: trashFill,
          child: _slot(trash),
        ),
      ],
    );
  }
}

/// Sky column whose bottom edge is a stamp you tear off.
///
/// Both gray sides run down to the outer tips. Only the lower half of each
/// diamond hangs below the band, so the edge reads as a torn stamp.
class CatalogStampBand extends StatelessWidget {
  const CatalogStampBand({
    super.key,
    required this.color,
    required this.lineColor,
    required this.bodyHeight,
    required this.child,
  });

  final Color color;
  final Color lineColor;
  final double bodyHeight;
  final Widget child;

  /// How far the outer tips hang below the waist. 45° so each tooth is a diamond.
  static double dropFor(
    double width, {
    double stroke = _StampBandPainter.strokeWidth,
  }) {
    return (width - stroke) / (catalogStampDiamonds + 1);
  }

  @override
  Widget build(BuildContext context) {
    final drop = dropFor(catalogActionExtent);
    return CustomPaint(
      painter: _StampBandPainter(
        color: color,
        lineColor: lineColor,
        bodyHeight: bodyHeight,
      ),
      child: SizedBox(
        width: catalogActionExtent,
        height: bodyHeight + drop,
        child: Align(
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
    );
  }
}

class _StampBandPainter extends CustomPainter {
  const _StampBandPainter({
    required this.color,
    required this.lineColor,
    required this.bodyHeight,
  });

  final Color color;
  final Color lineColor;
  final double bodyHeight;

  static const double strokeWidth = 1;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = strokeWidth / 2;
    const left = inset;
    final right = size.width - inset;
    final span = right - left;
    final step = span / (catalogStampDiamonds + 1);
    final depth = step;
    final waist = bodyHeight;
    final bottom = waist + depth;
    final valleyA = left + step;
    final middle = left + 2 * step;
    final valleyB = left + 3 * step;

    final fill = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, bottom)
      ..lineTo(valleyB, waist)
      ..lineTo(middle, bottom)
      ..lineTo(valleyA, waist)
      ..lineTo(0, bottom)
      ..close();
    canvas.drawPath(fill, Paint()..color = color);

    final line = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.miter
      ..strokeMiterLimit = 2
      ..isAntiAlias = true;

    // Side rules run to the outer tips. Only the lower teeth are outlined.
    canvas.drawPath(
      Path()
        ..moveTo(left, 0)
        ..lineTo(left, bottom)
        ..lineTo(valleyA, waist)
        ..lineTo(middle, bottom)
        ..lineTo(valleyB, waist)
        ..lineTo(right, bottom)
        ..lineTo(right, 0),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _StampBandPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.bodyHeight != bodyHeight;
  }
}

/// Announcement row: optional rounded frame, paper plane on the right.
class SubscriptionNoticeView extends StatelessWidget {
  const SubscriptionNoticeView({
    super.key,
    required this.text,
    required this.planeUrl,
    required this.frame,
    this.showPlane = true,
  });

  final String? text;
  final String? planeUrl;
  final bool frame;

  /// False when the profile card draws the plane in the refresh column.
  final bool showPlane;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = text?.trim() ?? '';
    final plane = planeUrl?.trim() ?? '';
    final drawPlane = showPlane && plane.isNotEmpty;
    if (body.isEmpty && !drawPlane) return const SizedBox.shrink();
    final telegram = plane.isNotEmpty && subscriptionPlaneIsTelegram(plane);
    final copy = Text(
      body,
      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
    );
    final framed = frame && body.isNotEmpty
        ? DecoratedBox(
            key: kSubscriptionNoticeFrameKey,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppBrand.radiusCard),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: copy,
            ),
          )
        : copy;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (body.isNotEmpty) Expanded(child: framed) else const Spacer(),
        if (drawPlane) ...[
          if (body.isNotEmpty) const SizedBox(width: 4),
          IconButton(
            key: kSubscriptionNoticePlaneKey,
            tooltip: telegram ? 'Telegram' : 'Link',
            onPressed: () => openSubscriptionPlane(plane),
            icon: AppIcon(
              telegram ? AppIcons.paperPlane : AppIcons.link,
              size: 22,
            ),
          ),
        ],
      ],
    );
  }
}

/// Opens the support link beside the description. Only http(s).
Future<bool> openSubscriptionPlane(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  if (uri.host.isEmpty) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
