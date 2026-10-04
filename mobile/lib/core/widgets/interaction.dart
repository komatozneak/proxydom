import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Reports pointer hover to a builder, and paints the pointer a desktop
/// expects.
///
/// The phone has no hover and no cursor; a window does, and an app that never
/// changes either reads as a phone layout stretched to fill a rectangle. Every
/// tappable row on desktop goes through here, so hover state is one line at the
/// call site and the cursor is never forgotten.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.onTap,
    this.cursor = SystemMouseCursors.click,
    this.focusNode,
    this.autofocus = false,
    this.onKeyActivate,
  });

  final Widget Function(BuildContext context, bool hovered) builder;

  /// Non-null makes the whole area clickable and gives it the pointer cursor.
  final VoidCallback? onTap;

  final MouseCursor cursor;

  final FocusNode? focusNode;

  final bool autofocus;

  /// Enter or Space on a focused area — the desktop equivalent of a tap.
  final VoidCallback? onKeyActivate;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;
  bool _focused = false;

  void _setHover(bool value) {
    if (_hovered == value || !mounted) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.builder(context, _hovered);

    if (widget.focusNode != null) {
      child = Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (value) {
          if (_focused == value || !mounted) return;
          setState(() => _focused = value);
        },
        onKeyEvent: (node, event) {
          final activate = widget.onKeyActivate;
          if (activate == null) return KeyEventResult.ignored;
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            activate();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      );
    }

    if (widget.onTap != null) {
      child = MouseRegion(
        cursor: widget.cursor,
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => _setHover(true),
          onTapUp: (_) => _setHover(false),
          onTapCancel: () => _setHover(false),
          child: child,
        ),
      );
    } else {
      child = MouseRegion(
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: child,
      );
    }

    // A desktop shows where the keyboard is. One ring, one colour, same rule
    // everywhere in the app.
    if (_focused) {
      child = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppBrand.actionSky, width: 2),
        ),
        child: child,
      );
    }
    return child;
  }
}