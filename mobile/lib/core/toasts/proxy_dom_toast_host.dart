import 'package:flutter/material.dart';

import '../ios_store_gates.dart';
import '../theme.dart';
import '../widgets/app_action_button.dart';
import '../widgets/app_icon.dart';
import 'proxy_dom_toast.dart';

/// How wide a window's alert is, and how far from the edges it stands.
const double kToastCornerWidth = 340;
const double kToastCornerInset = 24;

/// Key of the plate an alert is drawn on.\r
const Key kProxyDomToastPlate = Key('proxy-dom-toast');

/// Always-mounted host for the app's alerts.
///
/// It wraps the navigator rather than living inside a page, because an alert is
/// the window's, not a screen's: raised on the Servers tab it must not vanish
/// when the tab changes, and raised from a dialog it must sit above it.
class ProxyDomToastHost extends StatefulWidget {
  const ProxyDomToastHost({super.key, required this.child});

  final Widget child;

  @override
  State<ProxyDomToastHost> createState() => _ProxyDomToastHostState();
}

class _ProxyDomToastHostState extends State<ProxyDomToastHost>
    with SingleTickerProviderStateMixin {
  /// Built here, not lazily: [dispose] disposes it, and a lazily built one would
  /// be created *inside* dispose on every run where no alert ever appeared —
  /// which is a tree looking up an ancestor while it is being torn down.
  late final AnimationController _motion;

  /// What is on screen. It outlives [ProxyDomToasts.current] by one reverse
  /// animation, so an alert leaves instead of blinking out of existence.
  ProxyDomToast? _shown;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _shown = ProxyDomToasts.instance.current;
    if (_shown != null) _motion.value = 1;
    ProxyDomToasts.instance.addListener(_onToast);
  }

  @override
  void dispose() {
    ProxyDomToasts.instance.removeListener(_onToast);
    _motion.dispose();
    super.dispose();
  }

  void _onToast() {
    final toast = ProxyDomToasts.instance.current;
    if (toast == null) {
      _motion.reverse().whenComplete(() {
        if (!mounted) return;
        setState(() => _shown = null);
      });
      return;
    }
    setState(() => _shown = toast);
    _motion.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final toast = _shown;
    if (toast == null) return widget.child;
    // A window has a corner for this and a phone has a bottom edge: the same
    // alert drawn full width across a 1160px window is the phone's slab with
    // more of it, and it covers the keys of the page it is answering.
    final corner = windowsDesktop && MediaQuery.sizeOf(context).width >= 720;
    final bottom = (corner ? kToastCornerInset : 12) + toast.bottomInset;
    return Stack(
      children: [
        widget.child,
        Positioned(
          right: corner ? kToastCornerInset : 16,
          left: corner ? null : 16,
          width: corner ? kToastCornerWidth : null,
          bottom: bottom,
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, child) {
              final v = Curves.easeOutCubic.transform(_motion.value);
              return Opacity(
                opacity: v,
                child: FractionalTranslation(
                  // From the edge the alert lives on: the corner one comes in
                  // sideways, the phone one rises.
                  translation: Offset(corner ? 0.35 * (1 - v) : 0, 1.0 - v),
                  child: child,
                ),
              );
            },
            child: Align(
              alignment:
                  corner ? Alignment.centerRight : Alignment.bottomCenter,
              child: _Plate(toast: toast, corner: corner),
            ),
          ),
        ),
      ],
    );
  }
}

/// The plate itself: an edge that wears the tone, a line of words, and — on a
/// window — a way to send it away early.
class _Plate extends StatelessWidget {
  const _Plate({required this.toast, required this.corner});

  final ProxyDomToast toast;
  final bool corner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;
    final ink = dark ? AppBrand.inkDark : AppBrand.inkLight;
    final accent = switch (toast.tone) {
      ToastTone.info => AppBrand.mascotGold,
      ToastTone.success => dark ? AppBrand.mossLight : AppBrand.moss,
      ToastTone.failure => theme.colorScheme.error,
    };

    return Container(
      key: kProxyDomToastPlate,
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color:
            dark ? AppBrand.surfaceRaisedDark : AppBrand.surfaceElevatedLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (dark ? AppBrand.edgeDark : AppBrand.edgeLight)
              .withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: AppBrand.shadeSource.withValues(alpha: dark ? 0.45 : 0.14),
            blurRadius: 24,
            spreadRadius: -6,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The edge carries the news. Same grammar as the plate that is
            // chosen: a bar on the leading edge, never a filled pill.
            Container(width: 3, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                child: Text(
                  toast.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ),
            // A pointer invites a way out of a thing that is only in the way.
            if (corner)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                child: AppRingButton(
                  icon: AppIcons.x,
                  color: mute,
                  onPressed: ProxyDomToasts.instance.dismiss,
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  size: 26,
                  iconSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
