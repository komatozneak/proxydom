import 'dart:async';
import 'dart:io';

/// One application-level round trip through the active Windows tunnel.
///
/// The probe uses a literal IPv4 address so it does not depend on the exit
/// resolver, sends the same `generate_204` request the Android probe uses, and
/// waits for the first status byte before stopping the clock. A finished TCP
/// connect is not enough: the Hysteria2 stream is opened locally with
/// FastOpen before the node has answered.
typedef WindowsPingProbe = Future<int?> Function();

const _probeHost = '1.1.1.1';
const _probePort = 80;
const _probeHostHeader = 'cp.cloudflare.com';
const _probePath = '/generate_204';
const _connectTimeout = Duration(milliseconds: 2500);
const _readTimeout = Duration(milliseconds: 2500);
const _probeInterval = Duration(seconds: 5);
const _clearAfterMisses = 2;

/// Emits a fresh RTT every five seconds and keeps the previous value through
/// one missed probe. Two misses in a row emit `null`, which Home renders as
/// `—`; the stream is owned by the connected-state provider, so a disconnect
/// cancels the loop.
Stream<int?> windowsPingStream({
  WindowsPingProbe? probe,
  Duration interval = _probeInterval,
}) async* {
  final probeOnce = probe ?? probeWindowsTunnelRtt;
  var misses = 0;
  while (true) {
    final rtt = await probeOnce();
    if (rtt != null && rtt >= 1 && rtt <= 5000) {
      misses = 0;
      yield rtt;
    } else {
      misses++;
      if (misses >= _clearAfterMisses) yield null;
    }
    await Future<void>.delayed(interval);
  }
}

Future<int?> probeWindowsTunnelRtt({
  String host = _probeHost,
  int port = _probePort,
  String path = _probePath,
  String hostHeader = _probeHostHeader,
  Duration connectTimeout = _connectTimeout,
  Duration readTimeout = _readTimeout,
}) async {
  final stopwatch = Stopwatch()..start();
  Socket? socket;
  try {
    socket = await Socket.connect(host, port, timeout: connectTimeout);
    socket.write(
      'GET $path HTTP/1.0\r\n'
      'Host: $hostHeader\r\n'
      'Connection: close\r\n'
      '\r\n',
    );
    await socket.flush();

    final iterator = StreamIterator<List<int>>(socket.timeout(readTimeout));
    final line = <int>[];
    try {
      while (line.length < 64 && await iterator.moveNext()) {
        line.addAll(iterator.current);
        if (line.contains(10)) break;
      }
    } finally {
      await iterator.cancel();
    }

    final status = String.fromCharCodes(
      line.takeWhile((byte) => byte != 10 && byte != 13),
    );
    if (!status.startsWith('HTTP/1.') ||
        (!status.contains(' 204') && !status.contains(' 200'))) {
      return null;
    }

    stopwatch.stop();
    final elapsed = stopwatch.elapsedMilliseconds;
    if (elapsed < 1) return 1;
    if (elapsed > 5000) return null;
    return elapsed;
  } catch (_) {
    // The UI shows —; the next tick retries. No exception reaches Flutter.
    return null;
  } finally {
    socket?.destroy();
  }
}
