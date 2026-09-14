import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/referral/application/referral_providers.dart';
import '../features/referral/data/referral_code_format.dart';

/// Listen for `teremokconnect://ref?code=` (cold start + while running).
Future<void> attachReferralLinks(ProviderContainer container) async {
  final links = AppLinks();
  try {
    final initial = await links.getInitialLink();
    if (initial != null) {
      final code = referralCodeFromUri(initial);
      if (code != null && code.isNotEmpty) {
        container.read(pendingReferralCodeProvider.notifier).state = code;
      }
    }
  } catch (_) {
    // No initial link.
  }
  links.uriLinkStream.listen((uri) {
    final code = referralCodeFromUri(uri);
    if (code != null && code.isNotEmpty) {
      container.read(pendingReferralCodeProvider.notifier).state = code;
    }
  });
}
