#include "network_owner.h"
#include "process_host.h"
#include "protocol.h"
#include "session_store.h"
#include "session_supervisor.h"

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <shellapi.h>
#include <winsvc.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

const wchar_t* kServiceName = L"ProxyDomBroker";
const wchar_t* kPipeName = L"\\\\.\\pipe\\ProxyDomBrokerV3";
HANDLE g_io_thread = nullptr;
HANDLE g_writer_thread = nullptr;

SERVICE_STATUS_HANDLE g_status_handle = nullptr;
SERVICE_STATUS g_status{};
HANDLE g_stop = nullptr;
HANDLE g_reconciled = nullptr;

std::wstring exe_dir() {
  wchar_t path[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring text(path);
  const auto slash = text.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return L".";
  return text.substr(0, slash);
}

std::wstring installed_controller_path() {
  return L"C:\\Program Files\\Proxy Dom\\ProxyDomCtl.exe";
}

std::wstring sibling_controller_path() { return exe_dir() + L"\\ProxyDomCtl.exe"; }

std::wstring normalize_path(const std::wstring& path) {
  wchar_t full[MAX_PATH] = {};
  if (GetFullPathNameW(path.c_str(), MAX_PATH, full, nullptr) == 0) return path;
  return full;
}

bool same_path(const std::wstring& left, const std::wstring& right) {
  return CompareStringOrdinal(normalize_path(left).c_str(), -1, normalize_path(right).c_str(), -1, TRUE) ==
         CSTR_EQUAL;
}

bool client_is_controller(HANDLE pipe) {
  ULONG pid = 0;
  if (!GetNamedPipeClientProcessId(pipe, &pid)) return false;
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) return false;
  wchar_t image[MAX_PATH] = {};
  DWORD size = MAX_PATH;
  const BOOL ok = QueryFullProcessImageNameW(process, 0, image, &size);
  CloseHandle(process);
  if (!ok) return false;
  return same_path(image, installed_controller_path()) ||
         same_path(image, sibling_controller_path());
}

void set_state(DWORD state, DWORD hint) {
  g_status.dwCurrentState = state;
  g_status.dwWin32ExitCode = NO_ERROR;
  const bool pending = state == SERVICE_START_PENDING || state == SERVICE_STOP_PENDING;
  g_status.dwControlsAccepted =
      pending ? 0 : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_POWEREVENT | SERVICE_ACCEPT_PRESHUTDOWN);
  g_status.dwWaitHint = hint;
  g_status.dwCheckPoint = pending ? 1 : 0;
  SetServiceStatus(g_status_handle, &g_status);
}

struct App {
  Win32RouteTable routes;
  Win32Engine engine;
  Win32Resolver resolver;
  Win32ConnectivityProbe probe;
  Win32SessionFiles files;
  Win32TunnelLog log;
  Win32Sleeper sleeper;
  TunnelSupervisor supervisor;
  std::int64_t last_hello_log_ms_ = 0;
  CancelFlag cancel;
  std::mutex queue_mu;
  std::condition_variable queue_cv;
  std::deque<std::function<void()>> jobs;
  std::atomic<bool> stop{false};
  std::atomic<int> busy{0};
  std::thread worker;

  App()
      : engine(exe_dir() + L"\\sing-box.exe", proxy_dom_engine_config_path()),
        supervisor(routes, engine, resolver, probe, files, log, sleeper) {}

  void emit(const TunnelSnapshot& snap) {
    enqueue(state_event_v2(snap.generation, phase_name(snap.phase), code_name(snap.code), snap.message,
                           snap.cleanup_verified));
  }

  void post(std::function<void()> job) {
    {
      std::lock_guard<std::mutex> lock(queue_mu);
      jobs.push_back(std::move(job));
    }
    queue_cv.notify_all();
  }

  void loop() {
    supervisor.reconcile(cancel);
    if (g_reconciled != nullptr) SetEvent(g_reconciled);
    while (!stop.load()) {
      std::function<void()> job;
      {
        std::unique_lock<std::mutex> lock(queue_mu);
        queue_cv.wait_for(lock, std::chrono::seconds(2), [&] { return stop.load() || !jobs.empty(); });
        if (stop.load() && jobs.empty()) break;
        if (jobs.empty()) {
          job = [this] { supervisor.watchdog(cancel); };
        } else {
          job = std::move(jobs.front());
          jobs.pop_front();
        }
      }
      busy.fetch_add(1);
      job();
      busy.fetch_sub(1);
      queue_cv.notify_all();
    }
    busy.fetch_add(1);
    supervisor.disconnect(cancel);
    busy.fetch_sub(1);
    queue_cv.notify_all();
  }

  void start() {
    supervisor.set_observer([this](const TunnelSnapshot& snap) { emit(snap); });
    supervisor.set_ready_observer([this](std::int64_t generation) { enqueue(tun_ready_event(generation)); });
    // Only the broker knows the per-session secret, so the client the supervisor
    // builds can read the engine's connection list and nothing else can.
    supervisor.set_flow_factory(
        [](unsigned short port, const std::string& secret) { return make_flow_probe(port, secret); });
    worker = std::thread([this] { loop(); });
  }

  void join() {
    stop.store(true);
    cancel.request();
    queue_cv.notify_all();
    if (worker.joinable()) worker.join();
  }

  std::mutex out_mu;
  std::deque<std::string> outgoing;
  HANDLE kick = nullptr;
  // A state change with nobody attached is unreadable, and the next `hello`
  // re-emits the authoritative snapshot, so dropping it loses nothing. Without
  // this a tunnel kept alive across a detached window grows the queue forever.
  bool attached = false;

  void enqueue(const std::string& json) {
    {
      std::lock_guard<std::mutex> lock(out_mu);
      if (!attached) return;
      outgoing.push_back(json);
    }
    if (kick != nullptr) SetEvent(kick);
  }

  // Finish every reply before the next read. A read and a write outstanding
  // together never delivered connect after hello.
  bool write_one(HANDLE client, const std::string& json) {
    const std::string frame = encode_frame(json);
    if (frame.empty()) return false;
    OVERLAPPED ov{};
    ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (ov.hEvent == nullptr) return false;
    DWORD wrote = 0;
    const BOOL started = WriteFile(client, frame.data(), static_cast<DWORD>(frame.size()), &wrote, &ov);
    bool ok = started == TRUE;
    if (!ok && GetLastError() == ERROR_IO_PENDING) {
      ok = GetOverlappedResult(client, &ov, &wrote, TRUE) == TRUE;
    }
    CloseHandle(ov.hEvent);
    // The byte count of our own ack carries nothing the ack itself does not.
    // Journalling it once per frame buried every lifecycle event in noise.
    return ok && wrote == frame.size();
  }

  bool exchange(HANDLE client) {
    char chunk[4096];
    std::string inbound;
    OVERLAPPED read_ov{};
    read_ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    kick = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (read_ov.hEvent == nullptr || kick == nullptr) return false;

    auto close_events = [&] {
      HANDLE local = kick;
      kick = nullptr;
      if (local != nullptr) CloseHandle(local);
      CloseHandle(read_ov.hEvent);
    };
    auto drain = [&] {
      for (;;) {
        std::string json;
        std::string error;
        if (!take_frame(inbound, json, error)) return error.empty();
        if (!handle_command(json)) return false;
      }
    };
    auto flush = [&] {
      for (;;) {
        std::string json;
        {
          std::lock_guard<std::mutex> lock(out_mu);
          if (outgoing.empty()) return true;
          json = std::move(outgoing.front());
          outgoing.pop_front();
        }
        if (!write_one(client, json)) return false;
      }
    };

    while (!stop.load()) {
      if (!flush()) {
        close_events();
        return false;
      }
      ResetEvent(read_ov.hEvent);
      DWORD ignored = 0;
      const BOOL started = ReadFile(client, chunk, sizeof(chunk), &ignored, &read_ov);
      if (started) {
        if (ignored == 0) {
          close_events();
          return false;
        }
        inbound.append(chunk, ignored);
        if (!drain()) {
          close_events();
          return false;
        }
        continue;
      }
      if (GetLastError() != ERROR_IO_PENDING) {
        close_events();
        return false;
      }
      HANDLE waits[3] = {g_stop, read_ov.hEvent, kick};
      const DWORD which = WaitForMultipleObjects(3, waits, FALSE, 200);
      if (which == WAIT_OBJECT_0 || which == WAIT_FAILED) break;
      if (which == WAIT_OBJECT_0 + 1) {
        DWORD got = 0;
        if (!GetOverlappedResult(client, &read_ov, &got, FALSE) || got == 0) {
          close_events();
          return false;
        }
        inbound.append(chunk, got);
        if (!drain()) {
          close_events();
          return false;
        }
        continue;
      }
      CancelIoEx(client, &read_ov);
      DWORD got = 0;
      if (GetOverlappedResult(client, &read_ov, &got, TRUE) && got > 0) {
        inbound.append(chunk, got);
        if (!drain()) {
          close_events();
          return false;
        }
      }
    }
    close_events();
    return !stop.load();
  }

  void ack(const std::string& command, bool accepted, std::int64_t generation, const std::string& code,
           const std::string& message) {
    enqueue(ack_event(command, accepted, generation, code, message));
  }

  bool handle_command(const std::string& json) {
    ClientCommand command;
    std::string error;
    if (!parse_command(json, command, error)) {
      log.write(0, "frame", "protocol", 0);
      ack("connect", false, supervisor.snapshot().generation, "protocol", user_message(TunnelCode::Protocol, {}));
      return true;
    }
    if (command.protocol_version != 3) {
      ack(command.command, false, supervisor.snapshot().generation, "protocol", user_message(TunnelCode::Protocol, {}));
      return true;
    }
    // The controller pings every couple of seconds to hold the pipe lease.
    // Journalling each ping made 84% of the log heartbeat, which is how a
    // connect failure and a flow counter both end up invisible.
    if (command.command == "hello") {
      const auto stamp = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::steady_clock::now().time_since_epoch())
                             .count();
      if (stamp - last_hello_log_ms_ >= 30000) {
        last_hello_log_ms_ = stamp;
        log.write(supervisor.snapshot().generation, "hello", "rx", 0);
      }
      emit(supervisor.snapshot());
      return true;
    }
    // The window cannot delete the journal itself: under Program Data the
    // interactive user holds `Write` but not `Delete`, so the attempt failed on
    // the ACL no matter whether a tunnel was up. The service owns the files and
    // runs as SYSTEM, so it clears them and reports what survived.
    if (command.command == "clear_log") {
      const std::vector<std::string> remaining = clear_journal_files();
      std::string code = remaining.empty() ? "cleared" : "blocked";
      for (const std::string& name : remaining) {
        if (!code.empty()) code += " ";
        code += name;
      }
      log.write(supervisor.snapshot().generation, "logs", code, 0);
      ack("clear_log", remaining.empty(), supervisor.snapshot().generation, code, {});
      return true;
    }
    log.write(supervisor.snapshot().generation, command.command, "rx", 0);
    if (command.command == "prove") {
      const auto now = supervisor.snapshot();
      if (command.generation != now.generation || now.phase != TunnelPhase::Connecting) {
        ack("prove", false, now.generation, "generation", {});
        return true;
      }
      supervisor.note_user_proof(command.message == "ok", command.generation);
      ack("prove", true, command.generation, {}, {});
      return true;
    }
    if (command.command == "disconnect") {
      const auto now = supervisor.snapshot();
      if (command.generation != 0 && command.generation != now.generation) {
        ack("disconnect", false, now.generation, "generation", {});
        return true;
      }
      cancel.request();
      post([this] { supervisor.disconnect(cancel); });
      ack("disconnect", true, now.generation, {}, {});
      return true;
    }
    if (command.command != "connect") return true;
    const auto now = supervisor.snapshot();
    if (now.phase != TunnelPhase::Idle || !now.cleanup_verified) {
      const char* code = now.phase == TunnelPhase::Disconnecting || !now.cleanup_verified ? "cleanup_failed" : "busy";
      ack("connect", false, now.generation, code,
          user_message(code == std::string("busy") ? TunnelCode::Busy : TunnelCode::CleanupFailed, {}));
      return true;
    }
    cancel.reset();
    const BeginResult begin = supervisor.begin_connect();
    if (!begin.accepted) {
      ack("connect", false, begin.snap.generation, code_name(begin.snap.code), begin.snap.message);
      return true;
    }
    ConnectRequest request;
    request.uri = command.uri;
    request.direct_domains = command.direct_domains;
    request.force_proxy_domains = command.force_proxy_domains;
    request.udp_direct = command.udp_direct;
    if (command.direct_domains_truncated) {
      // A dropped exclusion row routes its site through the proxy and looks
      // like a routing bug. Say so in the log the app exports.
      log.write(begin.snap.generation, "connect", "direct_domains_truncated", 0);
    }
    post([this, request] { supervisor.run_connect(request, cancel); });
    ack("connect", true, begin.snap.generation, {}, {});
    return true;
  }

  void wait_until_settled() {
    std::unique_lock<std::mutex> lock(queue_mu);
    queue_cv.wait_for(lock, std::chrono::seconds(20), [&] {
      if (busy.load() != 0 || !jobs.empty()) return false;
      const TunnelSnapshot snap = supervisor.snapshot();
      return snap.cleanup_verified || snap.code == TunnelCode::CleanupFailed;
    });
  }

  void serve(HANDLE client) {
    {
      std::lock_guard<std::mutex> lock(out_mu);
      outgoing.clear();
      attached = true;
    }
    log.write(0, "pipe_client", "ok", 0);
    exchange(client);
    {
      std::lock_guard<std::mutex> lock(out_mu);
      attached = false;
    }
    const auto snap = supervisor.snapshot();
    log.write(snap.generation, "pipe_end", "win32", GetLastError());
    // The pipe is a channel, not a lease. Losing the controller must not take
    // the tunnel down: the service owns the session, the watchdog keeps
    // checking it, and the next window re-attaches with `hello`. Only an
    // explicit disconnect, a service stop, sleep, or a lost engine may stop it.
    const TeardownReason reason = TeardownReason::ClientGone;
    if (tunnel_should_stop(reason)) {
      cancel.request();
      post([this] { supervisor.disconnect(cancel); });
      wait_until_settled();
      return;
    }
    log.write(snap.generation, "detach", reason_name(reason), 0);
  }

};

App* g_app = nullptr;

DWORD WINAPI control_handler(DWORD control, DWORD event_type, LPVOID, LPVOID) {
  if (control == SERVICE_CONTROL_POWEREVENT && event_type == PBT_APMSUSPEND && g_app != nullptr) {
    // Sleep must not leave capture routes behind, and must not reconnect itself.
    const auto snap = g_app->supervisor.snapshot();
    if (snap.phase != TunnelPhase::Idle || !snap.cleanup_verified) {
      g_app->cancel.request();
      g_app->post([app = g_app] { app->supervisor.disconnect(app->cancel); });
    }
    return NO_ERROR;
  }
  if (control == SERVICE_CONTROL_STOP || control == SERVICE_CONTROL_PRESHUTDOWN) {
    if (g_app != nullptr) {
      g_app->stop.store(true);
      g_app->cancel.request();
      g_app->queue_cv.notify_all();
    }
    if (g_stop != nullptr) SetEvent(g_stop);
    if (g_io_thread != nullptr) CancelSynchronousIo(g_io_thread);
    if (g_writer_thread != nullptr) CancelSynchronousIo(g_writer_thread);
    set_state(SERVICE_STOP_PENDING, 20000);
    return NO_ERROR;
  }
  set_state(g_status.dwCurrentState, 0);
  return NO_ERROR;
}

void run_pipe(App& app) {
  if (g_io_thread != nullptr) CloseHandle(g_io_thread);
  g_io_thread = OpenThread(THREAD_TERMINATE, FALSE, GetCurrentThreadId());
  PSECURITY_DESCRIPTOR sd = nullptr;
  // LocalSystem pipes default to System integrity. A Medium window then gets
  // ERROR_ACCESS_DENIED even when the DACL names Authenticated Users.
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
          L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;AU)S:(ML;;NW;;;ME)",
          SDDL_REVISION_1, &sd, nullptr)) {
    app.log.write(0, "pipe_acl", "sddl", GetLastError());
    return;
  }
  SECURITY_ATTRIBUTES sa{};
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = sd;

  // A failing pipe loop used to write a line per iteration: five a second for
  // CreateNamedPipeW, and — because pipe_wait retried with a zero timeout —
  // as fast as the API would return for ERROR_PIPE_BUSY. 18 000 lines an hour
  // from one broken ACL fills the rotation before the service ever connects.
  // The first failure is written with its code, then the loop backs off and
  // reports every 100th, so a persistent fault stays visible without becoming
  // the log.
  unsigned long create_failures = 0;
  unsigned long wait_failures = 0;
  unsigned long reject_failures = 0;
  DWORD last_pipe_error = ERROR_SUCCESS;

  while (WaitForSingleObject(g_stop, 0) != WAIT_OBJECT_0) {
    HANDLE pipe = CreateNamedPipeW(
        kPipeName, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
        1, 65536, 65536, 5000, &sa);
    if (pipe == INVALID_HANDLE_VALUE) {
      const DWORD pipe_error = GetLastError();
      ++create_failures;
      if (create_failures == 1 || create_failures % 100 == 0) {
        app.log.write(0, "pipe_create", "win32", pipe_error);
      }
      last_pipe_error = pipe_error;
      // Back off up to two seconds. Stop must still be observed promptly, so
      // the wait stays a wait rather than a sleep.
      const DWORD backoff = create_failures > 8 ? 2000 : 200;
      if (WaitForSingleObject(g_stop, backoff) == WAIT_OBJECT_0) break;
      continue;
    }
    create_failures = 0;
    OVERLAPPED connect_ov{};
    connect_ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    bool ready = false;
    DWORD err = ERROR_INVALID_HANDLE;
    if (connect_ov.hEvent != nullptr) {
      const BOOL called = ConnectNamedPipe(pipe, &connect_ov);
      err = GetLastError();
      if (called || err == ERROR_PIPE_CONNECTED) {
        ready = true;
      } else if (err == ERROR_IO_PENDING) {
        HANDLE waits[2] = {g_stop, connect_ov.hEvent};
        const DWORD which = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
        if (which == WAIT_OBJECT_0 + 1) {
          DWORD unused = 0;
          ready = GetOverlappedResult(pipe, &connect_ov, &unused, FALSE) == TRUE;
          if (!ready) err = GetLastError();
        } else {
          CancelIoEx(pipe, &connect_ov);
          err = WAIT_TIMEOUT;
        }
      }
      CloseHandle(connect_ov.hEvent);
    }
    if (!ready) {
      ++wait_failures;
      if (wait_failures == 1 || wait_failures % 100 == 0) {
        app.log.write(0, "pipe_wait", "win32", err);
      }
      last_pipe_error = err;
      DisconnectNamedPipe(pipe);
      CloseHandle(pipe);
      // ERROR_PIPE_BUSY recurs while the previous instance is still closing;
      // an immediate retry turns that into a spin. 100 ms is short enough that
      // a real client reconnects without noticing.
      if (WaitForSingleObject(g_stop, 100) == WAIT_OBJECT_0) break;
      continue;
    }
    if (create_failures > 0 || wait_failures > 0) {
      // The loop recovered. Without this the throttle would silently swallow
      // the end of a fault, and the next failure would look like the first.
      app.log.write(0, "pipe_recovered", "last_win32", last_pipe_error);
    }
    create_failures = 0;
    wait_failures = 0;
    if (!client_is_controller(pipe)) {
      // GetLastError() here is meaningless — the rejection is this function's
      // own verdict, not a Win32 failure. Say what was refused instead.
      // Throttled like the others: a local process that spams the pipe must
      // not be able to fill the rotation.
      ++reject_failures;
      if (reject_failures == 1 || reject_failures % 100 == 0) {
        app.log.write(0, "reject_client", "not_controller", 0);
      }
      DisconnectNamedPipe(pipe);
      CloseHandle(pipe);
      continue;
    }
    reject_failures = 0;
    app.serve(pipe);
    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
  }
  LocalFree(sd);
}

void WINAPI service_main(DWORD, LPWSTR*) {
  g_status_handle = RegisterServiceCtrlHandlerExW(kServiceName, control_handler, nullptr);
  if (g_status_handle == nullptr) return;
  g_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  set_state(SERVICE_START_PENDING, 20000);
  WSADATA wsa{};
  WSAStartup(MAKEWORD(2, 2), &wsa);
  g_stop = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  g_reconciled = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  App app;
  g_app = &app;
  app.start();
  WaitForSingleObject(g_reconciled, 20000);
  set_state(SERVICE_RUNNING, 0);
  run_pipe(app);
  set_state(SERVICE_STOP_PENDING, 20000);
  app.join();
  g_app = nullptr;
  WSACleanup();
  CloseHandle(g_reconciled);
  CloseHandle(g_stop);
  set_state(SERVICE_STOPPED, 0);
}

int reconcile_standalone() {
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (scm != nullptr) {
    SC_HANDLE service = OpenServiceW(scm, kServiceName, SERVICE_STOP | SERVICE_QUERY_STATUS);
    if (service != nullptr) {
      SERVICE_STATUS status{};
      ControlService(service, SERVICE_CONTROL_STOP, &status);
      for (int i = 0; i < 40; ++i) {
        SERVICE_STATUS_PROCESS process{};
        DWORD needed = 0;
        if (!QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO, reinterpret_cast<LPBYTE>(&process), sizeof(process),
                                  &needed)) {
          break;
        }
        if (process.dwCurrentState == SERVICE_STOPPED) break;
        Sleep(500);
      }
      CloseServiceHandle(service);
    }
    CloseServiceHandle(scm);
  }
  WSADATA wsa{};
  WSAStartup(MAKEWORD(2, 2), &wsa);
  Win32RouteTable routes;
  Win32Engine engine(exe_dir() + L"\\sing-box.exe", proxy_dom_engine_config_path());
  Win32Resolver resolver;
  Win32ConnectivityProbe probe;
  Win32SessionFiles files;
  Win32TunnelLog log;
  Win32Sleeper sleeper;
  TunnelSupervisor supervisor(routes, engine, resolver, probe, files, log, sleeper);
  CancelFlag cancel;
  const TunnelSnapshot snap = supervisor.reconcile(cancel);
  WSACleanup();
  return snap.phase == TunnelPhase::Idle && snap.cleanup_verified ? 0 : 1;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  const bool reconcile = argc >= 2 && argv != nullptr && wcscmp(argv[1], L"--reconcile") == 0;
  if (argv != nullptr) LocalFree(argv);
  if (reconcile) return reconcile_standalone();
  SERVICE_TABLE_ENTRYW table[] = {{const_cast<LPWSTR>(kServiceName), service_main}, {nullptr, nullptr}};
  StartServiceCtrlDispatcherW(table);
  return 0;
}
