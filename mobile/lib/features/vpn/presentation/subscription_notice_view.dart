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
const kCatalogShareSlotKey = ValueKey<String>('catalog-share-slot');
const kCatalogTrashFillKey = ValueKey<String>('catalog-trash-fill');

/// Square action cell on the profile card. Refresh and trash match.
const double catalogActionExtent = 52;

/// Paper plane on the sky circle. The dark sheet uses the light band as ink.
Color catalogPlaneInk({required bool dark}) {
  return dark ? AppBrand.noticeBand : const Color(0xFF1578A8);
}

/// Trash cell. Solid margin ink, the orange square on the profile sketch.
Color catalogTrashFill(Color surface, {required bool dark}) {
  if (!dark) return AppBrand.paperMargin;
  return Color.alphaBlend(
    AppBrand.paperMargin.withValues(alpha: 0.92),
    surface,
  );
}

/// Title row: name, share, refresh, trash.
/// The announcement sits under the name. A support link's plane sits under
/// the refresh cell, with a trash-width gap so it does not land on the bin.
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

  /// Sky circle for share, and for the plane under the refresh cell.
  Widget _circleSlot(Widget child, {Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Center(
        child: Material(
          color: band,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 40,
            height: 40,
            child: child,
          ),
        ),
      ),
    );
  }

  /// Text under the title. The plane column lines up with refresh when that
  /// button is present, and with the right edge of the title row otherwise.
  Widget? _description(Widget? body, Widget? planeButton, bool hasRefresh) {
    if (body == null && planeButton == null) return null;
    if (planeButton == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
        child: body,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: body ?? const SizedBox.shrink(),
            ),
          ),
          if (hasRefresh) const SizedBox(width: catalogActionExtent),
          _circleSlot(planeButton, key: kCatalogPlaneSlotKey),
          const SizedBox(width: 1),
          const SizedBox(width: catalogActionExtent),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final refreshButton = refresh;
    final planeButton = plane;
    final body = notice;
    final description = _description(body, planeButton, refreshButton != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: catalogActionExtent,
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: title,
                  ),
                ),
              ),
              _circleSlot(share, key: kCatalogShareSlotKey),
              if (refreshButton != null)
                ColoredBox(
                  key: kCatalogRefreshBandKey,
                  color: band,
                  child: _slot(refreshButton, key: kCatalogRefreshSlotKey),
                ),
              _seam(),
              ColoredBox(
                key: kCatalogTrashFillKey,
                color: trashFill,
                child: _slot(trash),
              ),
            ],
          ),
        ),
        if (description != null) description,
      ],
    );
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

  /// False when the profile card draws the plane under the refresh cell.
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
      style: theme.textTheme.bodyMedium?.copyWith(
        height: 1.35,
        color: theme.colorScheme.onSurfaceVariant,
      ),
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
