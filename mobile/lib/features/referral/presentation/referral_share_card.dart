import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../application/referral_providers.dart';
import '../data/referral_api.dart';

/// Personal code + share URL when FEATURE_REFERRAL is on.
class ReferralShareCard extends ConsumerStatefulWidget {
  const ReferralShareCard({super.key});

  @override
  ConsumerState<ReferralShareCard> createState() => _ReferralShareCardState();
}

class _ReferralShareCardState extends ConsumerState<ReferralShareCard> {
  ReferralMe? _me;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = await ref.read(referralApiProvider).fetchMe();
    if (!mounted) return;
    setState(() {
      _me = me;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _me == null || !_me!.enabled || _me!.personalCode == null) {
      return const SizedBox.shrink();
    }
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final code = _me!.personalCode!;
    final url = _me!.shareUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.referralShareTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          l.referralShareBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 12),
        SelectableText(code, style: theme.textTheme.headlineSmall),
        if (url != null && url.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(url, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url ?? code));
          },
          child: Text(l.referralCopy),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
