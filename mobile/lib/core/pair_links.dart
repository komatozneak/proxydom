import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/application/pending_pair_token_provider.dart';
import '../features/auth/data/pair_token_format.dart';

/// Listen for `teremokconnect://pair?token=` (cold start + while running).
Future<void> attachPairLinks(ProviderContainer container) async {
  final links = AppLinks();
  try {
    final initial = await links.getInitialLink();
    if (initial != null) {
      final token = pairTokenFromUri(initial);
      if (token != null && token.isNotEmpty) {
        container.read(pendingPairTokenProvider.notifier).state = token;
      }
    }
  } catch (_) {
    // No initial link.
  }
  links.uriLinkStream.listen((uri) {
    final token = pairTokenFromUri(uri);
    if (token != null && token.isNotEmpty) {
      container.read(pendingPairTokenProvider.notifier).state = token;
    }
  });
}
