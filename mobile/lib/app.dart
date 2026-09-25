import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_locale.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/updates/update_check_service.dart';
import 'features/settings/application/locale_provider.dart';
import 'features/settings/application/theme_mode_provider.dart';
import 'features/vpn/data/hy2_link_parser.dart';
import 'features/vpn/data/subscription_link_inbox.dart';
import 'l10n/app_localizations.dart';

export 'core/app_locale.dart' show AppLocale;

class TeremokApp extends ConsumerWidget {
  const TeremokApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final locale = ref.watch(localeProvider).valueOrNull ?? AppLocale.current;

    return MaterialApp.router(
      title: 'Teremok Connect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocale.supportedLocales,
      localizationsDelegates: AppL10n.localizationsDelegates,
      routerConfig: AppRouter.config,
      builder: (context, child) {
        return _UpdateCheckHost(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

/// Runs a one-shot soft update check after the first frame.
class _UpdateCheckHost extends StatefulWidget {
  const _UpdateCheckHost({required this.child});

  final Widget child;

  @override
  State<_UpdateCheckHost> createState() => _UpdateCheckHostState();
}

class _UpdateCheckHostState extends State<_UpdateCheckHost> {
  var _started = false;
  String? _lastLink;
  StreamSubscription<Uri>? _links;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      UpdateCheckService().maybePrompt(context);
      _listenForSubscriptionLinks();
    });
  }

  void _listenForSubscriptionLinks() {
    final links = AppLinks();
    links.getInitialLink().then((uri) {
      if (!mounted || uri == null) return;
      _openSubscription(uri);
    });
    _links = links.uriLinkStream.listen(_openSubscription);
  }

  void _openSubscription(Uri uri) {
    final raw = uri.toString();
    if (raw == _lastLink) return;
    try {
      if (subscriptionDocumentTarget(raw) == null) return;
    } on FormatException {
      return;
    }
    _lastLink = raw;
    SubscriptionLinkInbox.offer(raw);
    AppRouter.config.go('/import');
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
