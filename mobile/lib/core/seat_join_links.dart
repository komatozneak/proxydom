import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/seat_code_format.dart';
import '../features/settings/application/seat_join_code_provider.dart';

/// Listen for `teremokconnect://join?code=` (cold start + while running).
Future<void> attachSeatJoinLinks(ProviderContainer container) async {
  final links = AppLinks();
  try {
    final initial = await links.getInitialLink();
    if (initial != null) {
      final code = seatCodeFromJoinUri(initial);
      if (code != null && code.isNotEmpty) {
        container.read(seatJoinCodeProvider.notifier).state = code;
      }
    }
  } catch (_) {
    // No initial link (normal cold start).
  }
  links.uriLinkStream.listen((uri) {
    final code = seatCodeFromJoinUri(uri);
    if (code != null && code.isNotEmpty) {
      container.read(seatJoinCodeProvider.notifier).state = code;
    }
  });
}
