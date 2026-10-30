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
import 'core/widgets/window_caption_bar.dart';
import 'features/settings/application/locale_provider.dart';
import 'features/settings/application/theme_mode_provider.dart';
import 'features/vpn/data/hy2_import_store.dart';
import 'features/vpn/data/vpn_controller.dart';
import 'features/vpn/data/hy2_link_parser.dart';
import 'features/vpn/data/share_link_parser.dart';
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
        Widget content = _UpdateCheckHost(
          child: windowsDesktop ? _WindowsExit(child: page) : page,
        );
        if (windowsDesktop) {
          content = _WindowsWindowFrame(child: content);
        }
        return ProxyDomToastHost(child: content);
      },
    );
  }
}

/// The window frame belongs to the window, not to one route: onboarding,
/// import and the shell all need the same caption and window buttons.
class _WindowsWindowFrame extends StatelessWidget {
  const _WindowsWindowFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final russian = Localizations.localeOf(context).languageCode == 'ru';
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          WindowCaptionBar(
            label: russian ? 'Прокси' : 'Proxy',
            ink: dark ? AppBrand.inkDark : AppBrand.inkLight,
          ),
          Expanded(child: child),
        ],
      ),
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
    _handleLink(uri);
  }

  Future<void> _handleLink(Uri uri) async {
    // `vmess://` carries base64 in the URI authority, and a Uri round trip
    // lowercases a host: the payload changes, the key stops decoding, and the
    // node is silently not added. The platform keeps the intent's own string,
    // so it is preferred over anything reconstructed here.
    final delivered = await VpnController.instance.takeRawLink();
    final raw = (delivered == null || delivered.isEmpty)
        ? uri.toString()
        : delivered;
    if (raw == _lastLink) return;
    // Two kinds of link arrive here: a document address from the bot's QR, and
    // a bare server key from another app's "share" sheet. The second one used
    // to be dropped on the floor — the manifest could route it, but this
    // handler only asked whether it was a document and gave up when it was not.
    var subscription = true;
    try {
      subscription = subscriptionDocumentTarget(raw) != null;
    } on FormatException {
      subscription = false;
    }
    if (!subscription && !isShareLinkLine(raw)) return;
    _lastLink = raw;
    if (!subscription) {
      // A single key handed over by the OS is a finished decision: the person
      // already chose this node by tapping "Открыть в Прокси Дом". Sending them
      // to the import screen only to press "Сохранить" added a second, empty
      // step — and a deep link that arrives while the app is already running
      // never reached the import screen at all, so the key looked ignored.
      _addKeyInBackground(raw);
      return;
    }
    SubscriptionLinkInbox.offer(raw);
    AppRouter.config.go('/import');
  }

  Future<void> _addKeyInBackground(String raw) async {
    try {
      final links = await Hy2ImportStore.instance.saveInput(raw);
      if (!mounted || links.isEmpty) return;
      SubscriptionLinkInbox.offer(raw);
      AppRouter.config.go('/home');
    } on Object {
      // A key the store refuses still belongs on the import screen, where the
      // reason is shown next to the field.
      SubscriptionLinkInbox.offer(raw);
      AppRouter.config.go('/import');
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Closing the window disconnects. Minimizing does not.
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
