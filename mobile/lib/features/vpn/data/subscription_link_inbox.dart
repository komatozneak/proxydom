/// Raw deeplink waiting for the import screen. Not a stored subscription.
class SubscriptionLinkInbox {
  SubscriptionLinkInbox._();

  static String? _pending;

  static void offer(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    _pending = text;
  }

  static String? take() {
    final value = _pending;
    _pending = null;
    return value;
  }

  /// Whether a link is waiting, without consuming it.
  ///
  /// Onboarding asks this: a key that arrived before the welcome screens were
  /// done used to be redirected to onboarding and then dropped on the floor,
  /// because only the import screen ever looked in the inbox.
  static bool get hasPending => _pending != null;
}
