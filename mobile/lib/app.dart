import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_locale.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/updates/update_check_service.dart';
import 'features/auth/application/pending_pair_token_provider.dart';
import 'features/referral/application/referral_providers.dart';
import 'features/settings/application/locale_provider.dart';
import 'features/settings/application/seat_join_code_provider.dart';
import 'features/settings/application/theme_mode_provider.dart';
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
        return _SeatJoinHost(
          child: _ReferralLinkHost(
            child: _PairLinkHost(
              child: _UpdateCheckHost(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
      },
    );
  }
}

/// Navigates to Devices when a `teremokconnect://join` code arrives.
class _SeatJoinHost extends ConsumerWidget {
  const _SeatJoinHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(seatJoinCodeProvider, (prev, next) {
      final code = next?.trim();
      if (code == null || code.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppRouter.config.go('/settings/devices');
      });
    });
    return child;
  }
}

/// Opens Account → promo when a `teremokconnect://ref` code arrives.
class _ReferralLinkHost extends ConsumerWidget {
  const _ReferralLinkHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(pendingReferralCodeProvider, (prev, next) {
      final code = next?.trim();
      if (code == null || code.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppRouter.config.go('/settings/account/promo');
      });
    });
    return child;
  }
}

/// Opens restore when a `teremokconnect://pair` token arrives.
class _PairLinkHost extends ConsumerWidget {
  const _PairLinkHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(pendingPairTokenProvider, (prev, next) {
      final token = next?.trim();
      if (token == null || token.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppRouter.config.go('/restore');
      });
    });
    return child;
  }
}

/// Runs a one-shot soft update check after the first frame (does not block auth).
class _UpdateCheckHost extends StatefulWidget {
  const _UpdateCheckHost({required this.child});

  final Widget child;

  @override
  State<_UpdateCheckHost> createState() => _UpdateCheckHostState();
}

class _UpdateCheckHostState extends State<_UpdateCheckHost> {
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      UpdateCheckService().maybePrompt(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
