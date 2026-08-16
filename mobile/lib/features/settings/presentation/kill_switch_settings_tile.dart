import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../vpn/data/vpn_controller.dart';

/// Status row for Android Always-on lockdown — not an in-app toggle.
///
/// Shows observed system state + a real button into VPN settings.
class KillSwitchSettingsTile extends StatefulWidget {
  const KillSwitchSettingsTile({
    super.key,
    this.queryLockdownState,
    this.openVpnSettings,
  });

  /// Test seams — default to [VpnController.instance].
  final Future<VpnLockdownState> Function()? queryLockdownState;
  final Future<bool> Function()? openVpnSettings;

  @override
  State<KillSwitchSettingsTile> createState() => KillSwitchSettingsTileState();
}

class KillSwitchSettingsTileState extends State<KillSwitchSettingsTile>
    with WidgetsBindingObserver {
  VpnLockdownState? _state;
  bool _checking = true;
  bool _opening = false;
  int _refreshGen = 0;
  bool _sawBackground = false;
  bool _disposed = false;

  /// Delays after resume — Secure/VpnService can lag briefly after Off→On.
  static const _resumeRetryDelays = <Duration>[
    Duration(milliseconds: 350),
    Duration(milliseconds: 900),
    Duration(milliseconds: 1800),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh(showSpinner: true));
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _refreshGen++; // cancel in-flight apply
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _sawBackground = true;
      return;
    }
    if (state == AppLifecycleState.resumed) {
      // Always re-query on resume; retries catch late system commits after
      // returning from VPN settings (especially Off→On).
      unawaited(_refreshAfterResume());
    }
  }

  Future<VpnLockdownState> _query() {
    final custom = widget.queryLockdownState;
    if (custom != null) return custom();
    return VpnController.instance.queryLockdownState();
  }

  Future<bool> _open() {
    final custom = widget.openVpnSettings;
    if (custom != null) return custom();
    return VpnController.instance.openVpnSettings();
  }

  Future<void> _refresh({required bool showSpinner}) async {
    final gen = ++_refreshGen;
    if (showSpinner && mounted) {
      setState(() => _checking = true);
    }
    final next = await _query();
    if (!mounted || gen != _refreshGen) return;
    setState(() {
      _state = next;
      _checking = false;
    });
  }

  Future<void> _refreshAfterResume() async {
    final aggressive = _sawBackground;
    _sawBackground = false;
    await _refresh(showSpinner: _state == null);
    // Always one short retry — system state can lag one tick after resume.
    // After VPN-settings return, poll a few more times (Off→On was sticky).
    final delays = aggressive
        ? _resumeRetryDelays
        : const <Duration>[Duration(milliseconds: 500)];
    for (final delay in delays) {
      await Future<void>.delayed(delay);
      if (!mounted || _disposed) return;
      await _refresh(showSpinner: false);
    }
  }

  Future<void> _launchVpnSettings() async {
    if (_opening) return;
    setState(() => _opening = true);
    // Leaving for system settings — resume retries apply on return.
    _sawBackground = true;
    final ok = await _open();
    if (!mounted) return;
    setState(() => _opening = false);
    if (!ok) {
      _sawBackground = false;
      final l = AppL10n.of(context);
      showTeremokSnackBar(context, l.settingsKillSwitchOpenFailed);
    }
  }

  String _statusText(AppL10n l) {
    if (_checking || _state == null) return l.settingsKillSwitchChecking;
    return switch (_state!) {
      VpnLockdownState.enabled => l.settingsKillSwitchOn,
      VpnLockdownState.alwaysOnOnly => l.settingsKillSwitchAlwaysOnOnly,
      VpnLockdownState.disabled => l.settingsKillSwitchOff,
      VpnLockdownState.unavailable => l.settingsKillSwitchUnavailable,
    };
  }

  String? _badgeText(AppL10n l) {
    if (_checking || _state == null) return null;
    return switch (_state!) {
      VpnLockdownState.enabled => l.settingsKillSwitchBadgeOn,
      VpnLockdownState.alwaysOnOnly => l.settingsKillSwitchBadgePartial,
      VpnLockdownState.disabled => l.settingsKillSwitchBadgeOff,
      VpnLockdownState.unavailable => l.settingsKillSwitchBadgeUnknown,
    };
  }

  Color _badgeColor(ThemeData theme) {
    if (_state == VpnLockdownState.enabled) {
      return AppBrand.success;
    }
    if (_state == VpnLockdownState.alwaysOnOnly) {
      return AppBrand.caution;
    }
    if (_state == VpnLockdownState.unavailable) {
      return theme.colorScheme.error;
    }
    return theme.colorScheme.onSurfaceVariant;
  }

  Color _statusColor(ThemeData theme) {
    if (_state == VpnLockdownState.alwaysOnOnly) {
      return AppBrand.caution;
    }
    if (_state == VpnLockdownState.unavailable) {
      return theme.colorScheme.error;
    }
    return theme.colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final badge = _badgeText(l);
    final badgeColor = _badgeColor(theme);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppBrand.oakWithOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const AppIcon(AppIcons.warning, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.settingsKillSwitch,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusText(l),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _statusColor(theme),
                      ),
                    ),
                  ],
                ),
              ),
              if (_checking)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: badgeColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed:
                  _opening ? null : () => unawaited(_launchVpnSettings()),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _opening
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.settingsKillSwitchOpenVpn),
            ),
          ),
        ],
      ),
    );
  }
}
