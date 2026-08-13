import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../data/vpn_disclosure_prefs.dart';

/// Play VPN policy: prominent disclosure + consent before first Connect.
///
/// Returns `true` if the user accepted (or already accepted earlier).
Future<bool> ensureVpnDisclosureAccepted(BuildContext context) async {
  if (await VpnDisclosurePrefs.isAccepted()) return true;
  if (!context.mounted) return false;

  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    useSafeArea: true,
    builder: (ctx) => const VpnDisclosureDialog(),
  );
  return accepted == true;
}

class VpnDisclosureDialog extends StatelessWidget {
  const VpnDisclosureDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
                    _Section(
                      title: l.vpnDisclosureVpnTitle,
                      body: l.vpnDisclosureVpnBody,
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: l.vpnDisclosureDataTitle,
                      body: l.vpnDisclosureDataBody,
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: l.vpnDisclosureNotTitle,
                      body: l.vpnDisclosureNotBody,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(AppConfig.privacyPolicyUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(l.settingsPrivacyPlaceholder),
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
