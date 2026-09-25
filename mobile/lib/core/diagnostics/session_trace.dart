import 'product_log.dart';

/// One connect attempt's clock. [ms] is milliseconds since [begin].
class SessionTrace {
  SessionTrace._();

  static final Stopwatch _watch = Stopwatch();
  static String? _sid;

  static void begin(String? sid) {
    _sid = sid;
    _watch
      ..reset()
      ..start();
    mark('begin');
  }

  static void mark(
    String phase, [
    Map<String, Object?> extra = const {},
  ]) {
    ProductLog.event(
      'vpn.phase',
      level: levelForVpnPhase(phase),
      fields: {
        if (_sid != null && _sid!.isNotEmpty) 'sid': _sid,
        'phase': phase,
        'ms': _watch.elapsedMilliseconds,
        ...extra,
      },
    );
  }

  static void resetForTest() {
    _sid = null;
    _watch
      ..stop()
      ..reset();
  }
}

/// Intermediate steps stay debug. A proved tunnel is info. A failed step is error.
ProductLogLevel levelForVpnPhase(String phase) {
  return switch (phase) {
    'fail' || 'Error' => ProductLogLevel.error,
    'ConnectedDegraded' || 'Degraded' => ProductLogLevel.warn,
    'connected' || 'ConnectedHealthy' => ProductLogLevel.info,
    _ => ProductLogLevel.debug,
  };
}
