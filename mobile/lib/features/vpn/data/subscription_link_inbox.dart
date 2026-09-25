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
}
