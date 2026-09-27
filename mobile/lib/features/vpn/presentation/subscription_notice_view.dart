import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../data/subscription_notice.dart';

const kSubscriptionNoticeFrameKey =
    ValueKey<String>('subscription-notice-frame');
const kSubscriptionNoticePlaneKey =
    ValueKey<String>('subscription-notice-plane');

/// Announcement row: optional rounded frame, paper plane on the right.
class SubscriptionNoticeView extends StatelessWidget {
  const SubscriptionNoticeView({
    super.key,
    required this.text,
    required this.planeUrl,
    required this.frame,
  });

  final String? text;
  final String? planeUrl;
  final bool frame;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = text?.trim() ?? '';
    final plane = planeUrl?.trim() ?? '';
    if (body.isEmpty && plane.isEmpty) return const SizedBox.shrink();
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
        if (plane.isNotEmpty) ...[
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
