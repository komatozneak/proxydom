import 'package:flutter/widgets.dart';

import 'product_log.dart';

/// One user action and how the UI answered. No clipboard text, keys, or URLs.
///
/// Navigation defaults to [ProductLogLevel.debug] so tab changes do not fill
/// the info pool. Callers that change the tunnel or the log pass a level.
class UiLog {
  UiLog._();

  static void action(
    String screen,
    String action, {
    ProductLogLevel level = ProductLogLevel.debug,
    String result = 'ok',
    String? reason,
    Map<String, Object?> extra = const {},
  }) {
    ProductLog.event(
      'ui.action',
      level: level,
      fields: {
        'screen': screen,
        'action': action,
        'result': result,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        ...extra,
      },
    );
  }
}

/// Screen changes. Dialogs without a path stay out so the ring is the
/// decisions, not every sheet animation.
class UiNavObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _route('open', route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _route('back', route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _route('replace', newRoute);
  }

  void _route(String action, Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || !name.startsWith('/')) return;
    final path = name.split('?').first;
    UiLog.action('nav', action, extra: {'route': path});
  }
}
