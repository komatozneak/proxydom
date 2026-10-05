import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_locale.dart';
import 'core/ios_store_gates.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/toasts/proxy_dom_toast_host.dart';
import 'core/updates/update_check_service.dart';
import 'features/settings/application/locale_provider.dart';
import 'features/settings/application/theme_mode_provider.dart';
import 'features/vpn/data/hy2_link_parser.dart';
import 'features/vpn/data/subscription_link_inbox.dart';
import 'features/vpn/data/windows_tunnel.dart';
import 'l10n/app_localizations.dart';

export 'core/app_locale.dart' show AppLocale;

class ProxyDomApp extends ConsumerWidget {
  const ProxyDomApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode =
        ref.watch(themeModeProvider).valueOrNull ?? ThemeMode.system;
    final locale = ref.watch(localeProvider).valueOrNull ?? AppLocale.current;

    return MaterialApp.router(
      title: 'Прокси Дом',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocale.supportedLocales,
      localizationsDelegates: AppL10n.localizationsDelegates,
      routerConfig: AppRouter.config,
      builder: (context, child) {
        final page = child ?? const SizedBox.shrink();
        return ProxyDomToastHost(
          child: _UpdateCheckHost(
            child: windowsDesktop ? _WindowsExit(child: page) : page,
          ),
        );
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

/// Closing the window disconnects. Minimizing does not (ADR 029).
class _WindowsExit extends StatefulWidget {
  const _WindowsExit({required this.child});

  final Widget child;

  @override
  State<_WindowsExit> createState() => _WindowsExitState();
}

class _WindowsExitState extends State<_WindowsExit> {
  late final AppLifecycleListener _listener = AppLifecycleListener(
    onExitRequested: () async {
      await WindowsTunnel.instance.disconnect();
      return AppExitResponse.exit;
    },
  );

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
