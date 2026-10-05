import 'dart:async';

import 'package:flutter/foundation.dart';

/// What an alert says about itself: a fact, an achievement, or a problem.
///
/// Only one colour ever changes. A window is not a phone: nothing here pulses,
/// nothing here shouts, and the one hue that means «it did not work» is the
/// only hue that carries weight.
enum ToastTone { info, success, failure }

/// How long an alert stays up. Long enough to read, short enough that a person
/// never has to dismiss what they just did themselves.
const Duration kProxyDomToastDuration = Duration(milliseconds: 2400);

/// One alert on screen.
@immutable
class ProxyDomToast {
  const ProxyDomToast(
    this.message, {
    this.tone = ToastTone.info,
    this.bottomInset = 0,
  });

  final String message;
  final ToastTone tone;

  /// Room the page keeps for its own controls along the bottom edge.
  ///
  /// Every page that owns a key bar pins it there, and an alert that sits on
  /// those keys is an alert over the controls that asked the question.
  final double bottomInset;
}

/// The app's alerts. One at a time, newest wins.
///
/// A queue is a phone idea: the phone has a thumb and no pointer. A window has
/// a corner, a mouse and a person who can see the whole page, so the right
/// answer to a second alert while one is up is the second alert, not a queue of
/// three to read through.
class ProxyDomToasts extends ChangeNotifier {
  ProxyDomToasts._();

  static final ProxyDomToasts instance = ProxyDomToasts._();

  ProxyDomToast? _current;
  ProxyDomToast? get current => _current;

  Timer? _timer;

  void show(
    String message, {
    ToastTone tone = ToastTone.info,
    double bottomInset = 0,
  }) {
    _timer?.cancel();
    _current = ProxyDomToast(message, tone: tone, bottomInset: bottomInset);
    notifyListeners();
    _timer = Timer(kProxyDomToastDuration, dismiss);
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }
}

/// Say something, briefly.
///
/// It is the app's only way to answer an action, and it is not a page's answer:
/// the alert belongs to the window, so it stays up when the page that raised it
/// is gone, and it is drawn in the corner the window has for such things.
void showProxyDomToast(
  String message, {
  ToastTone tone = ToastTone.info,
  double bottomInset = 0,
}) {
  ProxyDomToasts.instance.show(
    message,
    tone: tone,
    bottomInset: bottomInset,
  );
}
