import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../theme.dart';
import 'proxydom_brand.dart';
import 'windows_pane.dart';

/// The Windows caption, drawn by the app instead of by the system frame.
///
/// The window is created without WS_CAPTION so the lockup can be part of the
/// title bar rather than sitting under one. What the system used to do is not
/// reimplemented: the runner still answers HTCAPTION over this band, so
/// dragging, double-click-to-maximize and the snap layouts are the OS's own.
/// Only the buttons and the lockup are ours, and only the button rectangle is
/// handed back to the runner so it stays clickable instead of becoming a drag.
class WindowCaptionBar extends StatefulWidget {
  const WindowCaptionBar({
    super.key,
    required this.label,
    required this.ink,
    this.height = WindowsPane.captionHeight,
  });

  final String label;
  final Color ink;
  final double height;

  static const MethodChannel _chrome = MethodChannel('proxydom/window_chrome');

  @override
  State<WindowCaptionBar> createState() => _WindowCaptionBarState();
}

class _WindowCaptionBarState extends State<WindowCaptionBar> {
  static const double _buttonWidth = 46;
  static const double _buttonHeight = 32;

  /// Minimize and close. There is no maximize: the window is a utility with
  /// a fixed layout, and full screen only spreads it thin.
  static const int _buttonCount = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCaptionRegion());
  }

  @override
  void didUpdateWidget(covariant WindowCaptionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.height != widget.height) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncCaptionRegion());
    }
  }

  /// Tells the runner which slice of the caption is ours to click.
  ///
  /// Sent in logical pixels; the runner scales by the monitor DPI. Without it the
  /// whole band reports HTCAPTION and the buttons would start the window moving
  /// instead of closing it.
  Future<void> _syncCaptionRegion() async {
    final render = context.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    final buttonsLeft = render.size.width - _buttonCount * _buttonWidth;
    try {
      await WindowCaptionBar._chrome.invokeMethod<void>('setCaptionRegion', {
        'height': widget.height,
        'buttonsLeft': buttonsLeft,
        'buttonsTop': (widget.height - _buttonHeight) / 2,
        'buttonsRight': render.size.width,
        'buttonsBottom': (widget.height + _buttonHeight) / 2,
      });
    } on PlatformException {
      // Nothing to tell; the bar is decorative then.
    }
  }

  Future<void> _send(String method, [Object? arguments]) async {
    try {
      await WindowCaptionBar._chrome.invokeMethod<void>(method, arguments);
    } on PlatformException {
      // Ignore: the window may already be gone.
    }
  }

  void _invoke(String method, [Object? arguments]) {
    // Fire and forget on purpose: the channel call crosses to the runner, and a
    // failed invoke must never surface as an unhandled error in the UI.
    _send(method, arguments);
  }

  /// Minimize puts the window in the tray: a VPN keeps running with its window
  /// away. The runner draws the tray icon and its menu, in these words.
  void _hideToTray() {
    final l = AppL10n.of(context);
    _invoke('hideToTray', {
      'tooltip': widget.label,
      'open': l.trayOpen,
      'quit': l.trayQuit,
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // The navigation pane's column runs to the top of the window: over
          // the pane's width the caption is the pane, so the pane does not end
          // where the window frame begins.
          Positioned.fill(
            child: Semantics(
              label: widget.label,
              child: Align(
                alignment: Alignment.centerLeft,
                child: ValueListenableBuilder<double?>(
                  valueListenable: WindowsPane.currentWidth,
                  builder: (context, paneWidth, _) {
                    if (paneWidth == null) return const SizedBox.shrink();
                    final folded = paneWidth < WindowsPane.wideFrom;
                    final dark =
                        Theme.of(context).brightness == Brightness.dark;
                    return AnimatedContainer(
                      key: const ValueKey('caption-pane-column'),
                      duration: WindowsPane.fold,
                      curve: WindowsPane.foldCurve,
                      width: paneWidth,
                      decoration: BoxDecoration(
                        color: WindowsPane.panel(dark),
                        border: Border(right: WindowsPane.edge(dark)),
                      ),
                      // Folded, the app icon takes the corner over the pane,
                      // growing in as the title slides out of its way.
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: WindowsPane.compactWidth,
                          child: Center(
                            child: AnimatedOpacity(
                              key: const ValueKey('caption-folded-icon'),
                              opacity: folded ? 1 : 0,
                              duration: WindowsPane.fold,
                              curve: WindowsPane.foldCurve,
                              child: AnimatedScale(
                                scale: folded ? 1 : 0.5,
                                duration: WindowsPane.fold,
                                curve: WindowsPane.foldCurve,
                                child: const ProxyDomKeyIcon(size: 26),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          // The window's title, the way a Windows caption carries one: centred
          // over the pane while it is open, like the lockup at the pane's foot;
          // just past the pane's edge when it is folded.
          Positioned.fill(
            child: ExcludeSemantics(
              child: ValueListenableBuilder<double?>(
                valueListenable: WindowsPane.currentWidth,
                builder: (context, paneWidth, _) {
                  final folded =
                      paneWidth != null && paneWidth < WindowsPane.wideFrom;
                  return AnimatedPadding(
                    duration: WindowsPane.fold,
                    curve: WindowsPane.foldCurve,
                    padding: EdgeInsets.only(
                      left: folded
                          ? paneWidth + 14
                          : (paneWidth == null ? 16 : 0),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: folded ? null : paneWidth,
                        child: Text(
                          textAlign: folded || paneWidth == null
                              ? TextAlign.start
                              : TextAlign.center,
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: widget.ink.withValues(alpha: 0.6),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CaptionButton(
                  width: _buttonWidth,
                  height: _buttonHeight,
                  onTap: _hideToTray,
                  semanticLabel: 'Minimize',
                  painter: (c, s, h) => _drawMinimize(c, s, widget.ink),
                ),
                _CaptionButton(
                  width: _buttonWidth,
                  height: _buttonHeight,
                  onTap: () => _invoke('close'),
                  semanticLabel: 'Close',
                  close: true,
                  painter: (c, s, h) => _drawClose(
                    c,
                    s,
                    // The glyph flips to white on the red wash; a red cross on a
                    // red plate is the one thing that would actually disappear.
                    h ? AppBrand.lightSource : widget.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One caption button. Sized to the bar and painted, not an icon font: the
/// system glyphs are three specific shapes and an approximation of them is
/// worse than drawing them.
class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.width,
    required this.height,
    required this.onTap,
    required this.painter,
    required this.semanticLabel,
    this.close = false,
  });

  final double width;
  final double height;
  final VoidCallback onTap;
  final void Function(Canvas, Size, bool hovered) painter;
  final String semanticLabel;
  final bool close;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: widget.width,
            height: widget.height,
            alignment: Alignment.center,
            color: _hovered
                ? (widget.close
                    ? AppBrand.hoverCloseCaption
                    : AppBrand.hoverCaption)
                : AppBrand.idleCaption,
            child: CustomPaint(
              size: const Size(10, 10),
              painter: _GlyphPainter(widget.painter, _hovered),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.draw, this.hovered);

  final void Function(Canvas, Size, bool) draw;
  final bool hovered;

  @override
  void paint(Canvas canvas, Size size) {
    draw(canvas, size, hovered);
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) => old.hovered != hovered;
}

Paint _stroke(Color c) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1;

void _drawMinimize(Canvas c, Size s, Color color) {
  final p = _stroke(color)..strokeWidth = 1;
  c.drawLine(Offset(0, s.height / 2), Offset(s.width, s.height / 2), p);
}

void _drawClose(Canvas c, Size s, Color color) {
  final p = _stroke(color);
  c.drawLine(Offset(0, 0), Offset(s.width, s.height), p);
  c.drawLine(Offset(0, s.height), Offset(s.width, 0), p);
}
