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

const wchar_t* kServiceName = L"ProxyDomTunnelService";
const wchar_t* kPipeName = L"\\\\.\\pipe\\ProxyDomServicePipe";

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

std::wstring installed_ui_path() { return L"C:\\Program Files\\Proxy Dom\\proxy_dom.exe"; }

std::wstring sibling_ui_path() { return exe_dir() + L"\\proxy_dom.exe"; }

std::wstring normalize_path(const std::wstring& path) {
  wchar_t full[MAX_PATH] = {};
  if (GetFullPathNameW(path.c_str(), MAX_PATH, full, nullptr) == 0) return path;
  return full;
}

bool same_path(const std::wstring& left, const std::wstring& right) {
  return CompareStringOrdinal(normalize_path(left).c_str(), -1, normalize_path(right).c_str(), -1, TRUE) ==
         CSTR_EQUAL;
}

bool client_is_window(HANDLE pipe) {
  ULONG pid = 0;
  if (!GetNamedPipeClientProcessId(pipe, &pid)) return false;
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) return false;
  wchar_t image[MAX_PATH] = {};
  DWORD size = MAX_PATH;
  const BOOL ok = QueryFullProcessImageNameW(process, 0, image, &size);
  CloseHandle(process);
  if (!ok) return false;
  return same_path(image, installed_ui_path()) || same_path(image, sibling_ui_path());
}

void set_state(DWORD state, DWORD hint) {
  g_status.dwCurrentState = state;
  g_status.dwWin32ExitCode = NO_ERROR;
  const bool pending = state == SERVICE_START_PENDING || state == SERVICE_STOP_PENDING;
  g_status.dwControlsAccepted = pending ? 0 : SERVICE_ACCEPT_STOP;
  g_status.dwWaitHint = hint;
  g_status.dwCheckPoint = pending ? 1 : 0;
  SetServiceStatus(g_status_handle, &g_status);
}

struct App {
  Win32RouteTable routes;
  Win32Engine engine;
  Win32Resolver resolver;
  Win32SessionFiles files;
  Win32TunnelLog log;
  Win32Sleeper sleeper;
  TunnelSupervisor supervisor;
  CancelFlag cancel;
  std::mutex queue_mu;
  std::condition_variable queue_cv;
  std::deque<std::function<void()>> jobs;
  std::atomic<bool> stop{false};
  std::atomic<int> busy{0};
  std::mutex pipe_mu;
  HANDLE pipe = nullptr;
  std::thread worker;

  App()
      : engine(exe_dir() + L"\\sing-box.exe", proxy_dom_engine_config_path()),
        supervisor(routes, engine, resolver, files, log, sleeper) {}

  void emit(const TunnelSnapshot& snap) {
    std::lock_guard<std::mutex> lock(pipe_mu);
    if (pipe == nullptr) return;
    write_frame(pipe, state_event_v2(snap.generation, phase_name(snap.phase), code_name(snap.code), snap.message,
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
    worker = std::thread([this] { loop(); });
  }

  void join() {
    stop.store(true);
    cancel.request();
    queue_cv.notify_all();
    if (worker.joinable()) worker.join();
  }

  bool write_frame(HANDLE target, const std::string& json) {
    const std::string frame = encode_frame(json);
    if (frame.empty() || target == nullptr) return false;
    DWORD written = 0;
    return pipe_transfer(target, true, const_cast<char*>(frame.data()), static_cast<DWORD>(frame.size()),
                         &written) &&
           written == frame.size();
  }

  bool pipe_transfer(HANDLE target, bool writing, void* data, DWORD size, DWORD* transferred) {
    OVERLAPPED overlapped{};
    overlapped.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (overlapped.hEvent == nullptr) return false;
    const BOOL started = writing ? WriteFile(target, data, size, transferred, &overlapped)
                                 : ReadFile(target, data, size, transferred, &overlapped);
    if (!started && GetLastError() == ERROR_IO_PENDING) {
      HANDLE waits[2] = {g_stop, overlapped.hEvent};
      const DWORD which = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
      if (which != WAIT_OBJECT_0 + 1) {
        CancelIoEx(target, &overlapped);
        WaitForSingleObject(overlapped.hEvent, 1000);
        CloseHandle(overlapped.hEvent);
        return false;
      }
      if (!GetOverlappedResult(target, &overlapped, transferred, FALSE)) {
        CloseHandle(overlapped.hEvent);
        return false;
      }
      CloseHandle(overlapped.hEvent);
      return true;
    }
    CloseHandle(overlapped.hEvent);
    return started == TRUE;
  }

  bool read_frame(HANDLE target, std::string& json) {
    std::string buffer;
    while (g_stop == nullptr || WaitForSingleObject(g_stop, 50) != WAIT_OBJECT_0) {
      DWORD available = 0;
      if (!PeekNamedPipe(target, nullptr, 0, nullptr, &available, nullptr)) return false;
      if (available == 0) continue;
      char chunk[512];
      DWORD got = 0;
      const DWORD take = available > sizeof(chunk) ? static_cast<DWORD>(sizeof(chunk)) : available;
      if (!pipe_transfer(target, false, chunk, take, &got) || got == 0) return false;
      buffer.append(chunk, got);
      std::string error;
      if (take_frame(buffer, json, error)) return error.empty();
      if (!error.empty()) return false;
    }
    return false;
  }

  void ack(const std::string& command, bool accepted, std::int64_t generation, const std::string& code,
           const std::string& message) {
    std::lock_guard<std::mutex> lock(pipe_mu);
    if (pipe == nullptr) return;
    write_frame(pipe, ack_event(command, accepted, generation, code, message));
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
      std::lock_guard<std::mutex> lock(pipe_mu);
      pipe = client;
    }
    while (!stop.load()) {
      std::string json;
      if (!read_frame(client, json)) break;
      ClientCommand command;
      std::string error;
      if (!parse_command(json, command, error)) {
        ack("connect", false, supervisor.snapshot().generation, "protocol", user_message(TunnelCode::Protocol, {}));
        continue;
      }
      if (command.command == "hello") {
        emit(supervisor.snapshot());
        continue;
      }
      if (command.command == "disconnect") {
        const auto now = supervisor.snapshot();
        if (command.generation != 0 && command.generation != now.generation) {
          ack("disconnect", false, now.generation, "generation", {});
          continue;
        }
        cancel.request();
        post([this] { supervisor.disconnect(cancel); });
        ack("disconnect", true, now.generation, {}, {});
        continue;
      }
      if (command.command != "connect") continue;
      if (command.protocol_version != 2) {
        ack("connect", false, supervisor.snapshot().generation, "protocol", user_message(TunnelCode::Protocol, {}));
        continue;
      }
      const auto now = supervisor.snapshot();
      if (now.phase != TunnelPhase::Idle || !now.cleanup_verified) {
        const char* code = now.phase == TunnelPhase::Disconnecting || !now.cleanup_verified ? "cleanup_failed" : "busy";
        ack("connect", false, now.generation, code, user_message(code == std::string("busy") ? TunnelCode::Busy
                                                                                            : TunnelCode::CleanupFailed,
                                                                {}));
        continue;
      }
      cancel.reset();
      const BeginResult begin = supervisor.begin_connect();
      if (!begin.accepted) {
        ack("connect", false, begin.snap.generation, code_name(begin.snap.code), begin.snap.message);
        continue;
      }
      ConnectRequest request;
      request.uri = command.uri;
      request.direct_domains = command.direct_domains;
      post([this, request] { supervisor.run_connect(request, cancel); });
      ack("connect", true, begin.snap.generation, {}, {});
    }
    cancel.request();
    post([this] { supervisor.disconnect(cancel); });
    wait_until_settled();
    std::lock_guard<std::mutex> lock(pipe_mu);
    pipe = nullptr;
  }
};

App* g_app = nullptr;

DWORD WINAPI control_handler(DWORD control, DWORD, LPVOID, LPVOID) {
  if (control == SERVICE_CONTROL_STOP) {
    if (g_app != nullptr) {
      g_app->stop.store(true);
      g_app->cancel.request();
      g_app->queue_cv.notify_all();
    }
    if (g_stop != nullptr) SetEvent(g_stop);
    set_state(SERVICE_STOP_PENDING, 20000);
    return NO_ERROR;
  }
  set_state(g_status.dwCurrentState, 0);
  return NO_ERROR;
}

void run_pipe(App& app) {
  EXPLICIT_ACCESS_W access{};
  access.grfAccessPermissions = FILE_READ_DATA | FILE_WRITE_DATA | READ_CONTROL | SYNCHRONIZE;
  access.grfAccessMode = SET_ACCESS;
  access.grfInheritance = NO_INHERITANCE;
  access.Trustee.TrusteeForm = TRUSTEE_IS_SID;
  access.Trustee.TrusteeType = TRUSTEE_IS_WELL_KNOWN_GROUP;
  SID_IDENTIFIER_AUTHORITY nt = SECURITY_NT_AUTHORITY;
  PSID users = nullptr;
  AllocateAndInitializeSid(&nt, 1, SECURITY_AUTHENTICATED_USER_RID, 0, 0, 0, 0, 0, 0, 0, &users);
  access.Trustee.ptstrName = reinterpret_cast<LPWSTR>(users);
  PACL acl = nullptr;
  SetEntriesInAclW(1, &access, nullptr, &acl);
  SECURITY_DESCRIPTOR sd{};
  InitializeSecurityDescriptor(&sd, SECURITY_DESCRIPTOR_REVISION);
  SetSecurityDescriptorDacl(&sd, TRUE, acl, FALSE);
  SECURITY_ATTRIBUTES sa{};
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = &sd;

  while (WaitForSingleObject(g_stop, 0) != WAIT_OBJECT_0) {
    HANDLE pipe = CreateNamedPipeW(kPipeName, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
                                   PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1, 8192, 8192, 0, &sa);
    if (pipe == INVALID_HANDLE_VALUE) {
      if (WaitForSingleObject(g_stop, 200) == WAIT_OBJECT_0) break;
      continue;
    }
    OVERLAPPED overlapped{};
    overlapped.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    bool ready = false;
    if (overlapped.hEvent != nullptr) {
      const BOOL called = ConnectNamedPipe(pipe, &overlapped);
      const DWORD err = GetLastError();
      if (called || err == ERROR_PIPE_CONNECTED) {
        ready = WaitForSingleObject(g_stop, 0) != WAIT_OBJECT_0;
      } else if (err == ERROR_IO_PENDING) {
        HANDLE waits[2] = {g_stop, overlapped.hEvent};
        const DWORD which = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
        if (which == WAIT_OBJECT_0 + 1) {
          DWORD unused = 0;
          ready = GetOverlappedResult(pipe, &overlapped, &unused, FALSE) == TRUE;
        } else {
          CancelIoEx(pipe, &overlapped);
          WaitForSingleObject(overlapped.hEvent, 1000);
        }
      }
      CloseHandle(overlapped.hEvent);
    }
    if (!ready || !client_is_window(pipe)) {
      DisconnectNamedPipe(pipe);
      CloseHandle(pipe);
      continue;
    }
    app.serve(pipe);
    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
  }
  if (users != nullptr) FreeSid(users);
  if (acl != nullptr) LocalFree(acl);
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
  Win32SessionFiles files;
  Win32TunnelLog log;
  Win32Sleeper sleeper;
  TunnelSupervisor supervisor(routes, engine, resolver, files, log, sleeper);
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
