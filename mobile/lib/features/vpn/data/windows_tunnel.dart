import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'windows_tunnel_protocol.dart';

const String kWindowsFailureText =
    'Связь через выбранную строку не подтверждена';
const String kWindowsServiceMissing =
    'Служба Прокси Дом недоступна. Переустановите приложение';
const String kWindowsServiceStopped = 'Служба Прокси Дом остановлена';
const String kWindowsAlreadyOpen = 'Приложение уже запущено';

class WindowsConnectResult {
  const WindowsConnectResult({
    required this.ok,
    this.accepted = false,
    this.notice,
    this.code,
    this.generation = 0,
    this.cleanupVerified = true,
  });

  final bool ok;
  final bool accepted;
  final String? notice;
  final String? code;
  final int generation;
  final bool cleanupVerified;
}

/// Unprivileged window side of the Windows broker v3 contract (ADR 031).
///
/// Flutter never opens the LocalSystem named pipe. The sibling native
/// controller owns Windows IPC and exchanges newline-delimited JSON over its
/// standard streams. Closing the window closes that controller lease, which
/// makes the broker restore its owned routes.
class WindowsTunnel {
  WindowsTunnel._();

  static final WindowsTunnel instance = WindowsTunnel._();

  Process? _controller;
  IOSink? _commands;
  Future<void>? _starting;
  bool _connectPending = false;
  DateTime? _brokerCooldownUntil;

  /// True while a command is in flight, cleanup is unverified, or a failed
  /// hello is still in its short lock. Connected stays tappable.
  bool get nestLocked {
    if (_connectPending) return true;
    if ((phase == 'idle' || phase == 'disconnecting') && !cleanupVerified) {
      return true;
    }
    final until = _brokerCooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _coolBroker() {
    _brokerCooldownUntil = DateTime.now().add(const Duration(seconds: 3));
  }

  int generation = 0;
  String phase = 'idle';
  String? notice;
  String? code;
  bool cleanupVerified = true;

  final _states = StreamController<TunnelStateEvent>.broadcast();
  final List<TunnelStateEvent> _recent = [];
  int _seq = 0;

  Stream<TunnelStateEvent> get states => _states.stream;

  Future<void> _ensure() async {
    if (_controller != null && _commands != null) return;
    final starting = _starting;
    if (starting != null) return starting;
    final future = _startController();
    _starting = future;
    try {
      await future;
    } finally {
      _starting = null;
    }
  }

  Future<void> _startController() async {
    final stale = _controller;
    _controller = null;
    _commands = null;
    stale?.kill();

    final executable = File(Platform.resolvedExecutable);
    final controller = File(
      '${executable.parent.path}${Platform.pathSeparator}ProxyDomCtl.exe',
    );
    if (!controller.existsSync()) {
      _remember(_localFailure('broker_unavailable', kWindowsServiceMissing));
      throw StateError('ProxyDomCtl.exe is missing');
    }

    final process = await Process.start(
      controller.path,
      const ['session'],
      mode: ProcessStartMode.normal,
      runInShell: false,
    );
    _controller = process;
    _commands = process.stdin;
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_remember);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((_) {});
    unawaited(
      process.exitCode.then((_) {
        if (!identical(_controller, process)) return;
        _controller = null;
        _commands = null;
        if (generation != 0 && !cleanupVerified) {
          _remember(
            _localFailure(
              'cleanup_failed',
              'Связь со службой потеряна; служба восстанавливает сеть',
              restored: false,
            ),
          );
        }
      }),
    );
  }

  String _localFailure(
    String failureCode,
    String message, {
    bool restored = true,
  }) {
    return jsonEncode({
      'event': 'state',
      'generation': generation,
      'state': restored ? 'idle' : 'disconnecting',
      'code': failureCode,
      'message': message,
      'cleanup_verified': restored,
    });
  }

  Future<void> _send(Map<String, Object?> command) async {
    await _ensure();
    final sink = _commands;
    if (sink == null) throw StateError('controller stopped');
    sink.writeln(jsonEncode(command));
    await sink.flush().timeout(const Duration(seconds: 3));
  }

  void _remember(String json) {
    final parsed = TunnelStateEvent.parse(json);
    if (parsed == null) return;
    if (parsed.event == 'broker_closed') {
      _commands = null;
      _controller?.kill();
      _controller = null;
      final unsafe = _connectPending || phase != 'idle' || !cleanupVerified;
      _remember(
        _localFailure(
          unsafe ? 'cleanup_failed' : 'broker_unavailable',
          unsafe
              ? 'Связь со службой потеряна; служба восстанавливает сеть'
              : kWindowsServiceMissing,
          restored: !unsafe,
        ),
      );
      return;
    }
    final event = parsed.withSeq(++_seq);
    _recent.add(event);
    if (_recent.length > 64) _recent.removeAt(0);
    if (event.event == 'state') {
      phase = event.state.isEmpty ? phase : event.state;
      generation = event.generation;
      notice = event.message;
      code = event.code;
      if (event.cleanupVerified != null) {
        cleanupVerified = event.cleanupVerified!;
      }
      if (notice == kWindowsAlreadyOpen) exit(0);
      if (phase == 'idle' && notice == 'Соединение прервано') {
        onLinkLost?.call();
      }
    }
    _states.add(event);
  }

  Future<TunnelStateEvent> _waitFor(
    bool Function(TunnelStateEvent event) test, {
    required int afterSeq,
    required Duration timeout,
  }) {
    final completer = Completer<TunnelStateEvent>();
    late StreamSubscription<TunnelStateEvent> sub;
    sub = states.listen((event) {
      if (event.seq <= afterSeq || !test(event) || completer.isCompleted) {
        return;
      }
      completer.complete(event);
      unawaited(sub.cancel());
    });
    for (final event in _recent) {
      if (event.seq <= afterSeq || !test(event) || completer.isCompleted) {
        continue;
      }
      completer.complete(event);
      unawaited(sub.cancel());
      break;
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        unawaited(sub.cancel());
        throw TimeoutException('windows broker', timeout);
      },
    );
  }

  /// Fired when the broker drops a live tunnel and confirms local restore.
  void Function()? onLinkLost;

  Future<WindowsConnectResult> connect(
    String uri, {
    required List<String> directDomains,
  }) async {
    if (_connectPending || phase != 'idle' || !cleanupVerified) {
      return WindowsConnectResult(
        ok: false,
        notice: 'Подключение уже идёт',
        code: 'busy',
        generation: generation,
        cleanupVerified: cleanupVerified,
      );
    }
    _connectPending = true;
    final started = _seq;
    var accepted = false;
    try {
      await _send(tunnelHello());
      await _send(tunnelConnect(uri: uri, directDomains: directDomains));
      final ack = await _waitFor(
        (event) =>
            (event.event == 'ack' && event.command == 'connect') ||
            tunnelEventIsClientReject(event) ||
            (event.event == 'state' &&
                (event.code == 'broker_unavailable' ||
                    event.code == 'cleanup_failed')),
        afterSeq: started,
        timeout: const Duration(seconds: 5),
      );
      if (tunnelEventIsClientReject(ack)) {
        notice = ack.message;
        code = ack.code;
        return WindowsConnectResult(
          ok: false,
          notice: ack.message,
          code: ack.code,
          generation: ack.generation,
          cleanupVerified: ack.cleanupVerified ?? true,
        );
      }
      if (ack.event == 'state' || ack.accepted != true) {
        notice = ack.message;
        code = ack.code;
        if (ack.code == 'broker_unavailable') _coolBroker();
        return WindowsConnectResult(
          ok: false,
          accepted: ack.accepted == true,
          notice: ack.message,
          code: ack.code,
          generation: ack.generation,
          cleanupVerified: ack.cleanupVerified ?? cleanupVerified,
        );
      }
      accepted = true;
      final terminal = await _waitFor(
        (event) => tunnelEventIsConnectTerminal(event, ack.generation),
        afterSeq: started,
        timeout: kWindowsConnectWait,
      );
      return WindowsConnectResult(
        ok: terminal.state == 'connected',
        accepted: true,
        notice: terminal.message,
        code: terminal.code,
        generation: terminal.generation,
        cleanupVerified: terminal.cleanupVerified ?? false,
      );
    } on TimeoutException {
      if (accepted) {
        return WindowsConnectResult(
          ok: false,
          accepted: true,
          notice: kWindowsConnectingTimeoutCaption,
          code: 'connecting_timeout',
          generation: generation,
          cleanupVerified: cleanupVerified,
        );
      }
      _controller?.kill();
      _controller = null;
      _commands = null;
      _coolBroker();
      return const WindowsConnectResult(
        ok: false,
        notice: kWindowsServiceMissing,
        code: 'broker_unavailable',
      );
    } catch (_) {
      if (accepted) {
        return WindowsConnectResult(
          ok: false,
          accepted: true,
          notice: kWindowsConnectingTimeoutCaption,
          code: 'connecting_timeout',
          generation: generation,
          cleanupVerified: cleanupVerified,
        );
      }
      _coolBroker();
      return const WindowsConnectResult(
        ok: false,
        notice: kWindowsServiceMissing,
        code: 'broker_unavailable',
      );
    } finally {
      _connectPending = false;
    }
  }

  Future<void> refresh() async {
    final started = _seq;
    try {
      await _send(tunnelHello());
      await _waitFor(
        (event) => event.event == 'state',
        afterSeq: started,
        timeout: const Duration(seconds: 3),
      );
    } catch (_) {
      return;
    }
  }

  Future<bool> disconnect() async {
    if (_commands == null) return cleanupVerified;
    final started = _seq;
    try {
      await _send(tunnelDisconnect(generation));
      final event = await _waitFor(
        tunnelEventIsDisconnectTerminal,
        afterSeq: started,
        timeout: kWindowsDisconnectWait,
      );
      return tunnelCleanupSucceeded(event);
    } catch (_) {
      if (generation == 0) return true;
      return _failClosed().cleanupVerified;
    }
  }

  WindowsConnectResult _failClosed() {
    cleanupVerified = false;
    phase = 'disconnecting';
    code = 'cleanup_failed';
    notice = 'Сеть не восстановлена. Повторите отключение';
    final event = TunnelStateEvent(
      event: 'state',
      generation: generation,
      state: phase,
      code: code,
      message: notice,
      cleanupVerified: false,
    ).withSeq(++_seq);
    _recent.add(event);
    _states.add(event);
    return WindowsConnectResult(
      ok: false,
      notice: notice,
      code: code,
      generation: generation,
      cleanupVerified: false,
    );
  }

  /// One Windows process. A second launch shows the notice and returns false.
  static bool acquireSingleInstance() {
    if (!Platform.isWindows) return true;
    final kernel = DynamicLibrary.open('kernel32.dll');
    final createMutex = kernel.lookupFunction<
        IntPtr Function(Pointer<Void>, Int32, Pointer<Utf16>),
        int Function(Pointer<Void>, int, Pointer<Utf16>)>('CreateMutexW');
    final name = 'Local\\ProxyDomWindow'.toNativeUtf16();
    createMutex(nullptr, 0, name);
    malloc.free(name);
    final already = _lastWin32Error() == 183;
    if (!already) return true;
    _messageBox(kWindowsAlreadyOpen);
    return false;
  }
}

int _lastWin32Error() {
  final kernel = DynamicLibrary.open('kernel32.dll');
  final get = kernel.lookupFunction<Uint32 Function(), int Function()>(
    'GetLastError',
  );
  return get();
}

void _messageBox(String text) {
  final user = DynamicLibrary.open('user32.dll');
  final box = user.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>, int)>('MessageBoxW');
  final body = text.toNativeUtf16();
  final title = 'Прокси Дом'.toNativeUtf16();
  box(0, body, title, 0);
  malloc.free(body);
  malloc.free(title);
}
