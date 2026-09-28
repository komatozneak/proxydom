import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'windows_tunnel_protocol.dart';

const String kWindowsFailureText =
    'Сервер не отвечает: выход через туннель не подтверждён';
const String kWindowsServiceMissing =
    'Служба Прокси Дом не запущена. Переустановите приложение';
const String kWindowsServiceStopped =
    'Служба Прокси Дом остановлена. Запустите службу';
const String kWindowsAlreadyOpen = 'Приложение уже запущено';

class WindowsConnectResult {
  const WindowsConnectResult({
    required this.ok,
    this.notice,
    this.code,
    this.generation = 0,
    this.cleanupVerified = true,
  });

  final bool ok;
  final String? notice;
  final String? code;
  final int generation;
  final bool cleanupVerified;
}

/// Unelevated window side of `\\.\pipe\ProxyDomServicePipe` (ADR 029).
class WindowsTunnel {
  WindowsTunnel._();

  static final WindowsTunnel instance = WindowsTunnel._();

  SendPort? _commands;
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
    if (_commands != null) return;
    final ready = ReceivePort();
    final port = Completer<SendPort>();
    ready.listen((message) {
      if (message is SendPort && !port.isCompleted) {
        port.complete(message);
        return;
      }
      if (message is String) _remember(message);
    });
    await Isolate.spawn(_pipeActor, ready.sendPort);
    _commands = await port.future;
  }

  void _remember(String json) {
    final parsed = TunnelStateEvent.parse(json);
    if (parsed == null) return;
    final event = parsed.withSeq(++_seq);
    _recent.add(event);
    if (_recent.length > 64) _recent.removeAt(0);
    if (event.event == 'state') {
      phase = event.state.isEmpty ? phase : event.state;
      generation = event.generation;
      notice = event.message;
      code = event.code;
      if (event.cleanupVerified != null) cleanupVerified = event.cleanupVerified!;
      if (notice == kWindowsAlreadyOpen) exit(0);
      if (phase == 'idle' && notice == 'Соединение прервано') onLinkLost?.call();
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
      if (event.seq <= afterSeq || !test(event) || completer.isCompleted) return;
      completer.complete(event);
      sub.cancel();
    });
    for (final event in _recent) {
      if (event.seq <= afterSeq || !test(event) || completer.isCompleted) continue;
      completer.complete(event);
      sub.cancel();
      break;
    }
    return completer.future.timeout(timeout, onTimeout: () {
      sub.cancel();
      throw TimeoutException('windows tunnel', timeout);
    });
  }

  /// Fired when the service drops a live tunnel. Network changes do not.
  void Function()? onLinkLost;

  Future<WindowsConnectResult> connect(
    String uri, {
    required List<String> directDomains,
  }) async {
    await _ensure();
    final started = _seq;
    _commands!.send({
      'op': 'connect',
      'uri': uri,
      'domains': directDomains,
    });
    try {
      final ack = await _waitFor(
        (event) => event.event == 'ack' && event.command == 'connect',
        afterSeq: started,
        timeout: const Duration(seconds: 5),
      );
      if (ack.accepted != true) {
        notice = ack.message;
        code = ack.code;
        if (ack.code == 'cleanup_failed') {
          phase = 'disconnecting';
          cleanupVerified = false;
        }
        return WindowsConnectResult(
          ok: false,
          notice: ack.message,
          code: ack.code,
          generation: ack.generation,
          cleanupVerified: ack.cleanupVerified ?? cleanupVerified,
        );
      }
      final terminal = await _waitFor(
        (event) => tunnelEventIsConnectTerminal(event, ack.generation),
        afterSeq: started,
        timeout: kWindowsConnectWait,
      );
      return WindowsConnectResult(
        ok: terminal.state == 'connected',
        notice: terminal.message,
        code: terminal.code,
        generation: terminal.generation,
        cleanupVerified: terminal.cleanupVerified ?? false,
      );
    } on TimeoutException {
      return _failClosed();
    }
  }

  Future<void> refresh() async {
    await _ensure();
    final started = _seq;
    _commands!.send({'op': 'hello'});
    try {
      await _waitFor(
        (event) => event.event == 'state',
        afterSeq: started,
        timeout: const Duration(seconds: 3),
      );
    } on TimeoutException {
      return;
    }
  }

  Future<bool> disconnect() async {
    if (_commands == null) return cleanupVerified;
    final started = _seq;
    _commands!.send({
      'op': 'disconnect',
      'generation': generation,
    });
    try {
      final event = await _waitFor(
        tunnelEventIsDisconnectTerminal,
        afterSeq: started,
        timeout: kWindowsDisconnectWait,
      );
      return tunnelCleanupSucceeded(event);
    } on TimeoutException {
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

void _pipeActor(SendPort parent) {
  final inbox = ReceivePort();
  parent.send(inbox.sendPort);
  final session = _PipeSession(parent);
  inbox.listen((message) {
    final command = message as Map;
    final op = command['op'] as String;
    if (op == 'connect') {
      session.startConnect(
        command['uri'] as String,
        (command['domains'] as List).cast<String>(),
      );
      return;
    }
    if (op == 'disconnect') {
      session.startDisconnect(command['generation'] as int? ?? 0);
      return;
    }
    if (op == 'hello') session.hello();
  });
  Timer.periodic(const Duration(milliseconds: 20), (_) => session.poll());
}

class _PipeSession {
  _PipeSession(this._events);

  final SendPort _events;
  int? _handle;
  int generation = 0;
  final TunnelFrameBuffer _buffer = TunnelFrameBuffer();
  final _kernel = DynamicLibrary.open('kernel32.dll');
  final _advapi = DynamicLibrary.open('advapi32.dll');

  late final int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
      _createFile = _kernel.lookupFunction<
          IntPtr Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Uint32,
              Uint32, IntPtr),
          int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)>(
    'CreateFileW',
  );
  late final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      _readFile = _kernel.lookupFunction<
          Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
          int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)>(
    'ReadFile',
  );
  late final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      _writeFile = _kernel.lookupFunction<
          Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
          int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)>(
    'WriteFile',
  );
  late final int Function(int) _close = _kernel.lookupFunction<
      Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  bool get isOpen => _handle != null && _handle != -1;

  void hello() {
    final opened = _open();
    if (opened != null) {
      _events.send(jsonEncode({
        'event': 'state',
        'generation': generation,
        'state': 'idle',
        'code': 'core_start_failed',
        'message': opened['message'],
        'cleanup_verified': true,
      }));
      return;
    }
    if (!_writeJson(tunnelHello())) _emitCleanupFailed();
    poll();
  }

  void startConnect(String uri, List<String> domains) {
    final opened = _open();
    if (opened != null) {
      _events.send(jsonEncode({
        'event': 'ack',
        'command': 'connect',
        'accepted': false,
        'generation': generation,
        'code': 'core_start_failed',
        'message': opened['message'],
        'cleanup_verified': true,
      }));
      return;
    }
    if (!_writeJson(tunnelHello()) ||
        !_writeJson(tunnelConnect(uri: uri, directDomains: domains))) {
      _emitCleanupFailed();
    }
    poll();
  }

  void startDisconnect(int generation) {
    if (!isOpen) {
      // A pipe that never opened did not change routes. A pipe that closed
      // after Connect cannot prove that the service finished its restore.
      final untouched = generation == 0;
      _events.send(jsonEncode({
        'event': 'state',
        'generation': generation,
        'state': untouched ? 'idle' : 'disconnecting',
        'code': untouched ? null : 'cleanup_failed',
        'message': untouched ? null : 'Сеть не восстановлена. Повторите отключение',
        'cleanup_verified': untouched,
      }));
      return;
    }
    if (!_writeJson(tunnelDisconnect(generation))) _emitCleanupFailed();
    poll();
  }

  void poll() {
    if (!isOpen) return;
    if (!_readAvailable()) {
      _closeHandle();
      _emitCleanupFailed();
      return;
    }
    while (true) {
      final json = _buffer.take();
      if (json == null) return;
      final event = TunnelStateEvent.parse(json);
      if (event == null) continue;
      generation = event.generation;
      _events.send(json);
    }
  }

  void _emitCleanupFailed() {
    _events.send(jsonEncode({
      'event': 'state',
      'generation': generation,
      'state': 'disconnecting',
      'code': 'cleanup_failed',
      'message': 'Сеть не восстановлена. Повторите отключение',
      'cleanup_verified': false,
    }));
  }

  Map<String, Object?>? _open() {
    if (isOpen) return null;
    final name = r'\\.\pipe\ProxyDomServicePipe'.toNativeUtf16();
    final handle = _createFile(name, kTunnelPipeAccess, 0, nullptr, 3, 0, 0);
    malloc.free(name);
    if (handle == -1 || handle == 0) {
      return {
        'state': 'idle',
        'generation': generation,
        'message': _serviceNotice(),
      };
    }
    if (!_ownerIsLocalSystem(handle)) {
      _close(handle);
      return {
        'state': 'idle',
        'generation': generation,
        'message': kWindowsServiceMissing,
      };
    }
    _handle = handle;
    return null;
  }

  bool _ownerIsLocalSystem(int handle) {
    final owner = calloc<IntPtr>();
    final getSecurity = _advapi.lookupFunction<
        Uint32 Function(IntPtr, Uint32, Uint32, Pointer<IntPtr>, Pointer<IntPtr>,
            Pointer<IntPtr>, Pointer<IntPtr>, Pointer<IntPtr>),
        int Function(int, int, int, Pointer<IntPtr>, Pointer<IntPtr>, Pointer<IntPtr>,
            Pointer<IntPtr>, Pointer<IntPtr>)>('GetSecurityInfo');
    final rc = getSecurity(handle, 1, 1, owner, nullptr, nullptr, nullptr, nullptr);
    if (rc != 0) {
      calloc.free(owner);
      return false;
    }
    final local = calloc<Uint8>(68);
    final size = calloc<Uint32>();
    size.value = 68;
    final createSid = _advapi.lookupFunction<
        Int32 Function(Int32, Pointer<Void>, Pointer<Uint8>, Pointer<Uint32>),
        int Function(int, Pointer<Void>, Pointer<Uint8>, Pointer<Uint32>)>(
      'CreateWellKnownSid',
    );
    final equal = _advapi.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Void>),
        int Function(Pointer<Void>, Pointer<Void>)>('EqualSid');
    final made = createSid(22, nullptr, local, size);
    final same = made != 0 && equal(Pointer.fromAddress(owner.value), local.cast()) != 0;
    calloc.free(owner);
    calloc.free(local);
    calloc.free(size);
    return same;
  }

  String _serviceNotice() {
    final openScm = _advapi.lookupFunction<
        IntPtr Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int)>('OpenSCManagerW');
    final openService = _advapi.lookupFunction<
        IntPtr Function(IntPtr, Pointer<Utf16>, Uint32),
        int Function(int, Pointer<Utf16>, int)>('OpenServiceW');
    final query = _advapi.lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)>('QueryServiceStatus');
    final close = _advapi.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'CloseServiceHandle',
    );
    final scm = openScm(nullptr, nullptr, 1);
    if (scm == 0) return kWindowsServiceMissing;
    final name = 'ProxyDomTunnelService'.toNativeUtf16();
    final service = openService(scm, name, 4);
    malloc.free(name);
    if (service == 0) {
      close(scm);
      return _lastWin32Error() == 1060
          ? kWindowsServiceMissing
          : kWindowsServiceStopped;
    }
    final status = calloc<Uint32>(8);
    final ok = query(service, status);
    final state = ok != 0 ? status[1] : 0;
    calloc.free(status);
    close(service);
    close(scm);
    // SERVICE_STOPPED is 1. A running service (4) that still refused the pipe
    // is not "not installed".
    if (state == 1) return kWindowsServiceStopped;
    if (state == 4) return kWindowsFailureText;
    return kWindowsServiceMissing;
  }

  bool _writeJson(Map<String, Object?> message) {
    if (!isOpen) return false;
    final frame = encodeTunnelFrame(message);
    final native = calloc<Uint8>(frame.length);
    native.asTypedList(frame.length).setAll(0, frame);
    final written = calloc<Uint32>();
    final ok = _writeFile(_handle!, native, frame.length, written, nullptr);
    final sent = ok != 0 && written.value == frame.length;
    calloc.free(native);
    calloc.free(written);
    return sent;
  }

  bool _readAvailable() {
    if (!isOpen) return false;
    final peek = _kernel.lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Uint32>,
            Pointer<Uint32>),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Uint32>,
            Pointer<Uint32>)>('PeekNamedPipe');
    final available = calloc<Uint32>();
    final ok = peek(_handle!, nullptr, 0, nullptr, available, nullptr);
    if (ok == 0) {
      calloc.free(available);
      return false;
    }
    final count = available.value;
    calloc.free(available);
    if (count == 0) return true;
    final buf = calloc<Uint8>(count);
    final got = calloc<Uint32>();
    _readFile(_handle!, buf, count, got, nullptr);
    if (got.value > 0) {
      _buffer.add(buf.asTypedList(got.value));
    }
    calloc.free(buf);
    calloc.free(got);
    return true;
  }

  void _closeHandle() {
    if (!isOpen) return;
    _close(_handle!);
    _handle = null;
  }
}
