import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../data/vpn_disclosure_prefs.dart';
import 'vpn_platform_copy.dart';

/// Shown from the house tap, before the system VPN permission.
///
/// Decline leaves prefs unset so the next house tap shows this again.
class VpnDisclosureDialog extends StatelessWidget {
  const VpnDisclosureDialog({super.key});

  /// Returns true if the user already accepted, or accepts now.
  static Future<bool> ensureAccepted(BuildContext context) async {
    // Windows has no VpnService prompt and no Play disclosure. The desktop
    // onboarding already carries the privacy line, so a full-screen mobile
    // dialog here only made the PC build feel like a phone app.
    if (windowsDesktop) return true;
    if (await VpnDisclosurePrefs.isAccepted()) return true;
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const VpnDisclosureDialog(),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vpnTitle = vpnDisclosureVpnTitleForPlatform(l);
    final vpnBody = vpnDisclosureVpnBodyForPlatform(l);
    final dataBody = vpnDisclosureDataBodyForPlatform(l);

    return Dialog.fullscreen(
      backgroundColor: scheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                l.vpnDisclosureTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppBrand.primary,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.vpnDisclosureLead,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        height: 1.45,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _Bullet(text: l.vpnDisclosureBullet1),
                    const SizedBox(height: 12),
                    _Bullet(text: l.vpnDisclosureBullet2),
                    const SizedBox(height: 12),
                    _Bullet(text: l.vpnDisclosureBullet3),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => _showDetails(
                        context,
                        vpnTitle: vpnTitle,
                        vpnBody: vpnBody,
                        dataBody: dataBody,
                      ),
                      icon: const AppIcon(AppIcons.info, size: 18),
                      label: Text(l.vpnDisclosureMore),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: () async {
                      await VpnDisclosurePrefs.markAccepted();
                      if (context.mounted) Navigator.of(context).pop(true);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppBrand.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(l.vpnDisclosureAccept),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l.vpnDisclosureDecline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails(
    BuildContext context, {
    required String vpnTitle,
    required String vpnBody,
    required String dataBody,
  }) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.vpnDisclosureMore,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _Section(title: vpnTitle, body: vpnBody),
                const SizedBox(height: 16),
                _Section(
                  title: l.vpnDisclosureDataTitle,
                  body: dataBody,
                ),
                const SizedBox(height: 16),
                _Section(
                  title: l.vpnDisclosureNotTitle,
                  body: l.vpnDisclosureNotBody,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(AppConfig.privacyPolicyUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(l.settingsPrivacyPlaceholder),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l.vpnDisclosureClose),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppBrand.secondary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const AppIcon(
            AppIcons.check,
            size: 16,
            color: AppBrand.secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.45,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
