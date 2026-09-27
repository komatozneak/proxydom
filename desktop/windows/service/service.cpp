#include "cleanup.h"
#include "protocol.h"

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <aclapi.h>
#include <sddl.h>

#include <string>
#include <vector>

namespace {

const wchar_t* kServiceName = L"ProxyDomTunnelService";
const wchar_t* kPipeName = L"\\\\.\\pipe\\ProxyDomServicePipe";
const wchar_t* kFailure = L"Сервер не отвечает: выход через туннель не подтверждён";

SERVICE_STATUS_HANDLE g_status_handle = nullptr;
SERVICE_STATUS g_status{};
HANDLE g_stop = nullptr;

std::wstring exe_dir() {
  wchar_t path[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring text(path);
  const auto slash = text.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return L".";
  return text.substr(0, slash);
}

std::wstring installed_ui_path() {
  return L"C:\\Program Files\\Proxy Dom\\proxy_dom.exe";
}

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

void set_state(DWORD state) {
  g_status.dwCurrentState = state;
  g_status.dwWin32ExitCode = NO_ERROR;
  g_status.dwControlsAccepted = state == SERVICE_START_PENDING ? 0 : SERVICE_ACCEPT_STOP;
  SetServiceStatus(g_status_handle, &g_status);
}

DWORD WINAPI control_handler(DWORD control, DWORD, LPVOID, LPVOID) {
  if (control == SERVICE_CONTROL_STOP && g_stop != nullptr) SetEvent(g_stop);
  set_state(control == SERVICE_CONTROL_STOP ? SERVICE_STOP_PENDING : g_status.dwCurrentState);
  return NO_ERROR;
}

bool write_frame(HANDLE pipe, const std::string& json) {
  const std::string frame = encode_frame(json);
  if (frame.empty()) return false;
  DWORD written = 0;
  return WriteFile(pipe, frame.data(), static_cast<DWORD>(frame.size()), &written, nullptr) &&
         written == frame.size();
}

bool read_frame(HANDLE pipe, HANDLE stop, std::string& json) {
  std::string buffer;
  while (WaitForSingleObject(stop, 50) != WAIT_OBJECT_0) {
    DWORD available = 0;
    if (!PeekNamedPipe(pipe, nullptr, 0, nullptr, &available, nullptr)) return false;
    if (available == 0) continue;
    char chunk[512];
    DWORD got = 0;
    if (!ReadFile(pipe, chunk, sizeof(chunk), &got, nullptr) || got == 0) return false;
    buffer.append(chunk, got);
    std::string error;
    if (take_frame(buffer, json, error)) return error.empty();
    if (!error.empty()) return false;
  }
  return false;
}

std::string narrow(const wchar_t* text) {
  if (text == nullptr) return {};
  const int n = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (n <= 1) return {};
  std::string out(static_cast<std::size_t>(n - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, out.data(), n, nullptr, nullptr);
  return out;
}

bool resolve_ipv4(const std::string& host, std::string& ip) {
  ADDRINFOA hints{};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  ADDRINFOA* result = nullptr;
  if (getaddrinfo(host.c_str(), nullptr, &hints, &result) != 0 || result == nullptr) return false;
  char text[INET_ADDRSTRLEN] = {};
  const auto* addr = reinterpret_cast<sockaddr_in*>(result->ai_addr);
  inet_ntop(AF_INET, &addr->sin_addr, text, sizeof(text));
  freeaddrinfo(result);
  ip = text;
  return !ip.empty();
}

bool launch_core(const std::wstring& config, HANDLE* process, HANDLE* job) {
  std::wstring sing = exe_dir() + L"\\sing-box.exe";
  if (GetFileAttributesW(sing.c_str()) == INVALID_FILE_ATTRIBUTES) return false;
  *job = CreateJobObjectW(nullptr, nullptr);
  if (*job == nullptr) return false;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION info{};
  info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  SetInformationJobObject(*job, JobObjectExtendedLimitInformation, &info, sizeof(info));
  std::wstring command = L"\"" + sing + L"\" run -c \"" + config + L"\"";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESHOWWINDOW;
  startup.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION pi{};
  std::vector<wchar_t> mutable_command(command.begin(), command.end());
  mutable_command.push_back(L'\0');
  if (!CreateProcessW(sing.c_str(), mutable_command.data(), nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr, exe_dir().c_str(), &startup, &pi)) {
    CloseHandle(*job);
    *job = nullptr;
    return false;
  }
  if (!AssignProcessToJobObject(*job, pi.hProcess)) {
    ResumeThread(pi.hThread);
  } else {
    ResumeThread(pi.hThread);
  }
  CloseHandle(pi.hThread);
  *process = pi.hProcess;
  return true;
}

void stop_core(HANDLE& process, HANDLE& job) {
  if (process != nullptr) {
    TerminateProcess(process, 0);
    WaitForSingleObject(process, 5000);
    CloseHandle(process);
    process = nullptr;
  }
  if (job != nullptr) {
    CloseHandle(job);
    job = nullptr;
  }
  sweep_tunnel_leftovers();
}

void serve_client(HANDLE pipe) {
  std::int64_t generation = 0;
  bool busy = false;
  HANDLE process = nullptr;
  HANDLE job = nullptr;
  unsigned long physical = 0;
  std::string pinned_ip;
  const std::string failure = narrow(kFailure);

  auto fail = [&]() {
    stop_core(process, job);
    busy = false;
    write_frame(pipe, state_event(generation, "idle", &failure));
  };

  while (WaitForSingleObject(g_stop, 0) != WAIT_OBJECT_0) {
    std::string json;
    if (!read_frame(pipe, g_stop, json)) break;
    ClientCommand command;
    std::string error;
    if (!parse_command(json, command, error)) {
      write_frame(pipe, state_event(generation, "idle", &failure));
      continue;
    }
    if (command.command == "hello") {
      const char* state = busy ? "connecting" : "idle";
      write_frame(pipe, state_event(generation, state, nullptr));
      continue;
    }
    if (command.command == "disconnect") {
      if (command.generation != 0 && command.generation != generation) continue;
      write_frame(pipe, state_event(generation, "disconnecting", nullptr));
      stop_core(process, job);
      busy = false;
      write_frame(pipe, state_event(generation, "idle", nullptr));
      continue;
    }
    if (command.command != "connect") continue;
    if (busy) {
      const std::string text = "Подключение уже идёт";
      write_frame(pipe, state_event(generation, "idle", &text));
      continue;
    }
    ShareLine line;
    if (!parse_share_line(command.uri, line, error)) {
      write_frame(pipe, state_event(generation, "idle", &failure));
      continue;
    }
    ++generation;
    busy = true;
    write_frame(pipe, state_event(generation, "connecting", nullptr));
    std::string ip;
    if (!resolve_ipv4(line.host, ip) || !pin_server_route(ip) ||
        !physical_interface_for(ip, &physical)) {
      fail();
      continue;
    }
    pinned_ip = ip;
    const std::string config = build_singbox_config(line, ip, command.direct_domains);
    if (config.empty() || !write_session_file(config) || !launch_core(session_config_path(), &process, &job)) {
      fail();
      continue;
    }
    unsigned long tun_index = 0;
    bool ready = false;
    for (int i = 0; i < 50; ++i) {
      if (WaitForSingleObject(process, 0) == WAIT_OBJECT_0) break;
      if (tun_routes_ready(&tun_index)) {
        ready = true;
        break;
      }
      Sleep(100);
    }
    if (!ready || !prove_exit(tun_index)) {
      fail();
      continue;
    }
    write_frame(pipe, state_event(generation, "connected", nullptr));
    while (WaitForSingleObject(g_stop, 0) != WAIT_OBJECT_0) {
      if (process != nullptr && WaitForSingleObject(process, 0) == WAIT_OBJECT_0) {
        const std::string lost = "Соединение прервано";
        stop_core(process, job);
        busy = false;
        write_frame(pipe, state_event(generation, "idle", &lost));
        break;
      }
      unsigned long now = 0;
      if (!pinned_ip.empty() && physical_interface_for(pinned_ip, &now) && now != physical) {
        const std::string changed = "Сеть изменилась. Подключение остановлено.";
        stop_core(process, job);
        busy = false;
        write_frame(pipe, state_event(generation, "disconnecting", nullptr));
        write_frame(pipe, state_event(generation, "idle", &changed));
        break;
      }
      DWORD available = 0;
      if (!PeekNamedPipe(pipe, nullptr, 0, nullptr, &available, nullptr)) break;
      if (available == 0) {
        Sleep(200);
        continue;
      }
      std::string next;
      if (!read_frame(pipe, g_stop, next)) break;
      ClientCommand follow;
      std::string follow_error;
      if (!parse_command(next, follow, follow_error)) continue;
      if (follow.command == "disconnect" &&
          (follow.generation == 0 || follow.generation == generation)) {
        write_frame(pipe, state_event(generation, "disconnecting", nullptr));
        stop_core(process, job);
        busy = false;
        write_frame(pipe, state_event(generation, "idle", nullptr));
        break;
      }
    }
  }
  stop_core(process, job);
}

void run_pipe() {
  EXPLICIT_ACCESS_W access{};
  access.grfAccessPermissions = FILE_READ_DATA | FILE_WRITE_DATA | READ_CONTROL | SYNCHRONIZE;
  access.grfAccessMode = SET_ACCESS;
  access.grfInheritance = NO_INHERITANCE;
  access.Trustee.TrusteeForm = TRUSTEE_IS_SID;
  access.Trustee.TrusteeType = TRUSTEE_IS_WELL_KNOWN_GROUP;
  access.Trustee.ptstrName = const_cast<LPWSTR>(L"AU");
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
    HANDLE pipe = CreateNamedPipeW(kPipeName, PIPE_ACCESS_DUPLEX, PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
                                   1, 8192, 8192, 0, &sa);
    if (pipe == INVALID_HANDLE_VALUE) {
      Sleep(500);
      continue;
    }
    const BOOL connected = ConnectNamedPipe(pipe, nullptr) ? TRUE : (GetLastError() == ERROR_PIPE_CONNECTED);
    if (!connected || !client_is_window(pipe)) {
      DisconnectNamedPipe(pipe);
      CloseHandle(pipe);
      continue;
    }
    serve_client(pipe);
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
  set_state(SERVICE_START_PENDING);
  WSADATA wsa{};
  WSAStartup(MAKEWORD(2, 2), &wsa);
  g_stop = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  sweep_tunnel_leftovers();
  set_state(SERVICE_RUNNING);
  run_pipe();
  sweep_tunnel_leftovers();
  WSACleanup();
  set_state(SERVICE_STOPPED);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  SERVICE_TABLE_ENTRYW table[] = {{const_cast<LPWSTR>(kServiceName), service_main}, {nullptr, nullptr}};
  StartServiceCtrlDispatcherW(table);
  return 0;
}
