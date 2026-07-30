import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../beta/presentation/post_auth_gate_screen.dart';

/// Optional pre-auth Living House welcome (skippable → login).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      AppBrand.secondary.withOpacity(0.35),
                      AppBrand.surfaceLight,
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const AppIcon(
                  AppIcons.shield,
                  size: 56,
                  color: AppBrand.primary,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                l.appTitle,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppBrand.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l.welcomeHeadline,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l.welcomeBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.75),
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => markWelcomeAndGoLogin(context),
                child: Text(l.welcomeContinue),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => markWelcomeAndGoLogin(context),
                child: Text(l.welcomeSkip),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
