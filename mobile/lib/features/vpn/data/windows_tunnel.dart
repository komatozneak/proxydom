import 'dart:async';
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
  const WindowsConnectResult({required this.ok, this.notice, this.generation = 0});

  final bool ok;
  final String? notice;
  final int generation;
}

/// Unelevated window side of `\\.\pipe\ProxyDomServicePipe` (ADR 029).
class WindowsTunnel {
  WindowsTunnel._();

  static final WindowsTunnel instance = WindowsTunnel._();

  SendPort? _commands;
  int generation = 0;
  String phase = 'idle';
  String? notice;

  Future<void> _ensure() async {
    if (_commands != null) return;
    final ready = ReceivePort();
    final port = Completer<SendPort>();
    ready.listen((message) {
      if (message is SendPort && !port.isCompleted) {
        port.complete(message);
        return;
      }
      if (message is Map) {
        phase = message['state'] as String? ?? phase;
        generation = message['generation'] as int? ?? generation;
        notice = message['message'] as String?;
        if (notice == kWindowsAlreadyOpen) exit(0);
        final lost = notice == 'Соединение прервано';
        if (phase == 'idle' && lost) onLinkLost?.call();
      }
    });
    await Isolate.spawn(_pipeActor, ready.sendPort);
    _commands = await port.future;
  }

  /// Fired when the service drops a live tunnel. Network changes do not.
  void Function()? onLinkLost;

  Future<WindowsConnectResult> connect(
    String uri, {
    required List<String> directDomains,
  }) async {
    await _ensure();
    final reply = ReceivePort();
    _commands!.send({
      'op': 'connect',
      'uri': uri,
      'domains': directDomains,
      'port': reply.sendPort,
    });
    final message = await reply.first as Map;
    reply.close();
    phase = message['state'] as String? ?? 'idle';
    generation = message['generation'] as int? ?? generation;
    notice = message['message'] as String?;
    if (notice == kWindowsAlreadyOpen) {
      exit(0);
    }
    return WindowsConnectResult(
      ok: phase == 'connected',
      notice: notice,
      generation: generation,
    );
  }

  Future<void> disconnect() async {
    if (_commands == null) return;
    final reply = ReceivePort();
    _commands!.send({
      'op': 'disconnect',
      'generation': generation,
      'port': reply.sendPort,
    });
    final message = await reply.first as Map;
    reply.close();
    phase = message['state'] as String? ?? 'idle';
    notice = message['message'] as String?;
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
  final queue = <Map<dynamic, dynamic>>[];
  inbox.listen((message) => queue.add(message as Map));
  Timer.periodic(const Duration(milliseconds: 40), (_) {
    if (queue.isEmpty) {
      session.poll();
      return;
    }
    final command = queue.removeAt(0);
    final reply = command['port'] as SendPort;
    final op = command['op'] as String;
    if (op == 'connect') {
      final result = session.connect(
        command['uri'] as String,
        (command['domains'] as List).cast<String>(),
      );
      reply.send(result);
      return;
    }
    session.disconnect(command['generation'] as int? ?? 0);
    reply.send({
      'state': 'idle',
      'generation': session.generation,
      'message': null,
    });
  });
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

  Map<String, Object?> connect(String uri, List<String> domains) {
    final opened = _open();
    if (opened != null) return opened;
    _writeJson(tunnelHello());
    _awaitState();
    _writeJson(tunnelConnect(uri: uri, directDomains: domains));
    final event = _awaitTerminal();
    generation = event?.generation ?? generation;
    return {
      'state': event?.state ?? 'idle',
      'generation': generation,
      'message': event?.message,
    };
  }

  void disconnect(int generation) {
    if (!isOpen) return;
    _writeJson(tunnelDisconnect(generation));
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final event = _awaitState();
      if (event == null || event.state == 'idle') break;
    }
    _closeHandle();
  }

  void poll() {
    if (!isOpen) return;
    _readAvailable();
    final json = _buffer.take();
    if (json == null) return;
    final event = TunnelStateEvent.parse(json);
    if (event == null) return;
    generation = event.generation;
    _events.send({
      'state': event.state,
      'generation': event.generation,
      'message': event.message,
    });
  }

  Map<String, Object?>? _open() {
    if (isOpen) return null;
    final name = r'\\.\pipe\ProxyDomServicePipe'.toNativeUtf16();
    final handle = _createFile(name, 0x80000000 | 0x40000000, 0, nullptr, 3, 0, 0);
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
    final stopped = ok != 0 && status[1] == 1;
    calloc.free(status);
    close(service);
    close(scm);
    return stopped ? kWindowsServiceStopped : kWindowsServiceMissing;
  }

  void _writeJson(Map<String, Object?> message) {
    final frame = encodeTunnelFrame(message);
    final native = calloc<Uint8>(frame.length);
    native.asTypedList(frame.length).setAll(0, frame);
    final written = calloc<Uint32>();
    _writeFile(_handle!, native, frame.length, written, nullptr);
    calloc.free(native);
    calloc.free(written);
  }

  void _readAvailable() {
    if (!isOpen) return;
    final peek = _kernel.lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Uint32>,
            Pointer<Uint32>),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Uint32>,
            Pointer<Uint32>)>('PeekNamedPipe');
    final available = calloc<Uint32>();
    final ok = peek(_handle!, nullptr, 0, nullptr, available, nullptr);
    final count = ok == 0 ? 0 : available.value;
    calloc.free(available);
    if (count == 0) return;
    final buf = calloc<Uint8>(count);
    final got = calloc<Uint32>();
    _readFile(_handle!, buf, count, got, nullptr);
    if (got.value > 0) {
      _buffer.add(buf.asTypedList(got.value));
    }
    calloc.free(buf);
    calloc.free(got);
  }

  TunnelStateEvent? _awaitState() {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      _readAvailable();
      final json = _buffer.take();
      if (json == null) {
        sleep(const Duration(milliseconds: 30));
        continue;
      }
      return TunnelStateEvent.parse(json);
    }
    return null;
  }

  TunnelStateEvent? _awaitTerminal() {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      _readAvailable();
      final json = _buffer.take();
      if (json == null) {
        sleep(const Duration(milliseconds: 30));
        continue;
      }
      final event = TunnelStateEvent.parse(json);
      if (event == null) continue;
      generation = event.generation;
      if (event.state == 'connected' || event.state == 'idle') return event;
    }
    return TunnelStateEvent(
      generation: generation,
      state: 'idle',
      message: kWindowsFailureText,
    );
  }

  void _closeHandle() {
    if (!isOpen) return;
    _close(_handle!);
    _handle = null;
  }
}
