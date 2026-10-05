import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'proxydom_mark.dart';

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
    this.height = 40,
  });

  final String label;
  final Color ink;
  final double height;

  static const MethodChannel _chrome = MethodChannel('proxydom/window_chrome');

  /// Horizontal inset of the lockup from the window edge.
  static const double _inset = 16;

  @override
  State<WindowCaptionBar> createState() => _WindowCaptionBarState();
}

class _WindowCaptionBarState extends State<WindowCaptionBar> {
  static const double _buttonWidth = 46;
  static const double _buttonHeight = 32;

  int _buttonCount = 3;
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCaptionRegion());
    _askMaximized();
  }

  @override
  void didUpdateWidget(covariant WindowCaptionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.height != widget.height) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncCaptionRegion());
    }
  }

  Future<void> _askMaximized() async {
    try {
      final value = await WindowCaptionBar._chrome.invokeMethod<bool>(
        'isMaximized',
      );
      if (value != null && mounted) setState(() => _maximized = value);
    } on PlatformException {
      // Pre-channel runner, or a test host: the bar still draws.
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

  Future<void> _send(String method) async {
    try {
      await WindowCaptionBar._chrome.invokeMethod<void>(method);
      if (method == 'toggleMaximize') _askMaximized();
    } on PlatformException {
      // Ignore: the window may already be gone.
    }
  }

  void _invoke(String method) {
    // Fire and forget on purpose: the channel call crosses to the runner, and a
    // failed invoke must never surface as an unhandled error in the UI.
    _send(method);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // Transparent to the pointer everywhere except the buttons. Dragging
          // is the runner's job, not this widget's.
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(
                left: WindowCaptionBar._inset,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ProxyDomLockup(
                  label: widget.label,
                  ink: widget.ink,
                  // The house takes the whole height of the band: the caption is
                  // a frame, and a mark that stops short of its top and bottom
                  // reads as an icon dropped into a bar rather than as the name.
                  size: widget.height,
                ),
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
                  onTap: () => _invoke('minimize'),
                  semanticLabel: 'Minimize',
                  painter: (c, s, h) => _drawMinimize(c, s, widget.ink),
                ),
                _CaptionButton(
                  width: _buttonWidth,
                  height: _buttonHeight,
                  onTap: () => _invoke('toggleMaximize'),
                  semanticLabel: _maximized ? 'Restore' : 'Maximize',
                  painter: (c, s, h) => _drawMaximize(
                    c,
                    s,
                    widget.ink,
                    restore: _maximized,
                  ),
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

void _drawMaximize(Canvas c, Size s, Color color, {bool restore = false}) {
  final p = _stroke(color);
  if (!restore) {
    c.drawRect(
      Rect.fromLTWH(0.5, 0.5, s.width - 1, s.height - 1),
      p,
    );
    return;
  }
  // Two offset squares: the back one peeks out top-right, the front one is the
  // window that would come back.
  c.drawRect(
    Rect.fromLTWH(2.5, 0.5, s.width - 3, s.height - 3),
    p,
  );
  c.drawRect(Rect.fromLTWH(0.5, 2.5, s.width - 3, s.height - 3), p);
  c.drawLine(Offset(0.5, 2.5), Offset(s.width - 2.5, 2.5), p);
}

void _drawClose(Canvas c, Size s, Color color) {
  final p = _stroke(color);
  c.drawLine(Offset(0, 0), Offset(s.width, s.height), p);
  c.drawLine(Offset(0, s.height), Offset(s.width, 0), p);
}