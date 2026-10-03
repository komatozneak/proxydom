#include "protocol.h"

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <winsvc.h>

#include <atomic>
#include <cctype>
#include <cstring>
#include <deque>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>

#pragma comment(lib, "ws2_32.lib")

namespace {

const wchar_t* kPipeName = L"\\\\.\\pipe\\ProxyDomBrokerV3";
const wchar_t* kServiceName = L"ProxyDomBroker";

bool trusted_server(HANDLE pipe) {
  ULONG pid = 0;
  if (!GetNamedPipeServerProcessId(pipe, &pid) || pid == 0) return false;
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (scm == nullptr) return false;
  SC_HANDLE service = OpenServiceW(scm, kServiceName, SERVICE_QUERY_STATUS);
  if (service == nullptr) {
    CloseServiceHandle(scm);
    return false;
  }
  SERVICE_STATUS_PROCESS info{};
  DWORD needed = 0;
  const bool ok =
      QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO, reinterpret_cast<LPBYTE>(&info),
                           sizeof(info), &needed) == TRUE;
  CloseServiceHandle(service);
  CloseServiceHandle(scm);
  return ok && info.dwCurrentState == SERVICE_RUNNING && info.dwProcessId == pid;
}

HANDLE open_broker() {
  for (int attempt = 0; attempt < 30; ++attempt) {
    HANDLE pipe =
        CreateFileW(kPipeName, FILE_READ_DATA | FILE_WRITE_DATA | SYNCHRONIZE, 0, nullptr,
                    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (pipe != INVALID_HANDLE_VALUE) {
      if (trusted_server(pipe)) return pipe;
      CloseHandle(pipe);
      SetLastError(ERROR_SERVICE_NOT_ACTIVE);
      return INVALID_HANDLE_VALUE;
    }
    const DWORD error = GetLastError();
    if (error != ERROR_PIPE_BUSY && error != ERROR_FILE_NOT_FOUND && error != ERROR_SEM_TIMEOUT) break;
    WaitNamedPipeW(kPipeName, 100);
  }
  return INVALID_HANDLE_VALUE;
}

std::mutex g_write_mu;

bool write_json(HANDLE pipe, const std::string& json) {
  const std::string frame = encode_frame(json);
  if (frame.empty()) return false;
  std::lock_guard<std::mutex> lock(g_write_mu);
  DWORD written = 0;
  return WriteFile(pipe, frame.data(), static_cast<DWORD>(frame.size()),
                   &written, nullptr) &&
         written == frame.size();
}

std::int64_t generation_of(const std::string& json) {
  const std::string key = "\"generation\":";
  const auto at = json.find(key);
  if (at == std::string::npos) return 0;
  try {
    return std::stoll(json.substr(at + key.size()));
  } catch (...) {
    return 0;
  }
}

// Gate 3. No IP_UNICAST_IF: the route table must carry this socket.
bool user_ingress_204() {
  WSADATA wsa{};
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return false;
  addrinfo hints{};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  addrinfo* result = nullptr;
  if (getaddrinfo("cp.cloudflare.com", "80", &hints, &result) != 0 || result == nullptr) {
    WSACleanup();
    return false;
  }
  SOCKET sock = socket(result->ai_family, result->ai_socktype, result->ai_protocol);
  if (sock == INVALID_SOCKET) {
    freeaddrinfo(result);
    WSACleanup();
    return false;
  }
  u_long nb = 1;
  ioctlsocket(sock, FIONBIO, &nb);
  const int rc = connect(sock, result->ai_addr, static_cast<int>(result->ai_addrlen));
  freeaddrinfo(result);
  if (rc != 0 && WSAGetLastError() != WSAEWOULDBLOCK) {
    closesocket(sock);
    WSACleanup();
    return false;
  }
  fd_set write_set;
  FD_ZERO(&write_set);
  FD_SET(sock, &write_set);
  timeval tv{};
  tv.tv_sec = 7;
  if (select(0, nullptr, &write_set, nullptr, &tv) <= 0) {
    closesocket(sock);
    WSACleanup();
    return false;
  }
  const char* request =
      "GET /generate_204 HTTP/1.1\r\nHost: cp.cloudflare.com\r\nConnection: close\r\n\r\n";
  send(sock, request, static_cast<int>(strlen(request)), 0);
  std::string body;
  char chunk[512];
  for (int i = 0; i < 20 && body.find("\r\n") == std::string::npos; ++i) {
    fd_set read_set;
    FD_ZERO(&read_set);
    FD_SET(sock, &read_set);
    timeval wait{};
    wait.tv_sec = 1;
    if (select(0, &read_set, nullptr, nullptr, &wait) <= 0) break;
    const int got = recv(sock, chunk, sizeof(chunk), 0);
    if (got <= 0) break;
    body.append(chunk, got);
  }
  closesocket(sock);
  WSACleanup();
  return body.find(" 204") != std::string::npos;
}

bool read_json(HANDLE pipe, std::string& json) {
  std::string buffer;
  char bytes[8192];
  while (true) {
    DWORD got = 0;
    const BOOL ok = ReadFile(pipe, bytes, sizeof(bytes), &got, nullptr);
    if (!ok && GetLastError() != ERROR_MORE_DATA) return false;
    if (got == 0) return false;
    buffer.append(bytes, got);
    std::string error;
    if (take_frame(buffer, json, error)) return error.empty();
    if (!error.empty() || buffer.size() > kFrameMaxBody + 4) return false;
  }
}

void print_client_error(const std::string& code) {
  std::string safe = "protocol";
  bool token = !code.empty();
  for (unsigned char c : code) {
    if (!std::isalnum(c) && c != '_') token = false;
  }
  if (token) safe = code;
  std::cout
      << "{\"event\":\"client_error\",\"generation\":0,\"state\":\"\","
         "\"code\":\""
      << safe
      << "\",\"message\":\"Команда подключения не передана\","
         "\"cleanup_verified\":true}"
      << std::endl;
}

void print_unavailable(DWORD error) {
  std::cout
      << "{\"event\":\"state\",\"generation\":0,\"state\":\"idle\","
         "\"code\":\"broker_unavailable\","
         "\"message\":\"Служба Прокси Дом недоступна. Переустановите приложение\","
         "\"cleanup_verified\":true,\"win32\":"
      << error << "}" << std::endl;
}

int status_once(HANDLE pipe) {
  if (!write_json(
          pipe,
          "{\"command\":\"hello\",\"protocol_version\":3}")) {
    return 3;
  }
  std::string response;
  if (!read_json(pipe, response)) return 4;
  std::cout << response << std::endl;
  return 0;
}

int session(HANDLE pipe) {
  // Stdin is queued on another thread. Every pipe read and write stays here.
  // A blocking ReadFile beside WriteFile never delivered connect after hello.
  std::mutex queue_mu;
  std::deque<std::string> lines;
  std::atomic<bool> stdin_open{true};
  std::thread stdin_thread([&] {
    std::string line;
    while (std::getline(std::cin, line)) {
      if (line.empty()) continue;
      std::lock_guard<std::mutex> lock(queue_mu);
      lines.push_back(std::move(line));
    }
    stdin_open.store(false);
  });

  std::string inbound;
  std::int64_t last_proved_gen = 0;
  while (stdin_open.load()) {
    DWORD avail = 0;
    if (!PeekNamedPipe(pipe, nullptr, 0, nullptr, &avail, nullptr)) break;
    if (avail > 0) {
      char bytes[8192];
      DWORD got = 0;
      const DWORD want = avail > sizeof(bytes) ? static_cast<DWORD>(sizeof(bytes)) : avail;
      if (!ReadFile(pipe, bytes, want, &got, nullptr) || got == 0) break;
      inbound.append(bytes, got);
      for (;;) {
        std::string response;
        std::string error;
        if (!take_frame(inbound, response, error)) {
          if (!error.empty()) stdin_open.store(false);
          break;
        }
        std::cout << response << std::endl;
        if (response.find("\"event\":\"state\"") != std::string::npos &&
            response.find("\"state\":\"idle\"") != std::string::npos) {
          last_proved_gen = 0;
        }
        if (response.find("\"event\":\"tun_ready\"") == std::string::npos) continue;
        const auto generation = generation_of(response);
        if (!prove_generation_due(last_proved_gen, generation)) continue;
        const bool ok = user_ingress_204();
        if (!write_json(pipe, std::string("{\"command\":\"prove\",\"protocol_version\":3,\"generation\":") +
                                  std::to_string(generation) + ",\"message\":\"" + (ok ? "ok" : "fail") + "\"}")) {
          stdin_open.store(false);
          break;
        }
        last_proved_gen = generation;
      }
    }

    std::string line;
    {
      std::lock_guard<std::mutex> lock(queue_mu);
      if (!lines.empty()) {
        line = std::move(lines.front());
        lines.pop_front();
      }
    }
    if (!line.empty()) {
      ClientCommand command;
      std::string error;
      if (!parse_command(line, command, error) || command.protocol_version != 3) {
        print_client_error(error.empty() ? "protocol" : error);
      } else if (!write_json(pipe, line)) {
        print_client_error("frame");
        break;
      }
    } else if (avail == 0) {
      Sleep(10);
    }
  }

  std::cout
      << "{\"event\":\"broker_closed\",\"generation\":0,\"state\":\"\","
         "\"code\":\"broker_unavailable\",\"message\":null}"
      << std::endl;
  CloseHandle(pipe);
  stdin_thread.detach();
  return 0;
}

}  // namespace

#ifndef PROXY_DOM_CTL_LIBRARY
int wmain(int argc, wchar_t** argv) {
  const bool status = argc >= 2 && wcscmp(argv[1], L"status") == 0;
  const bool interactive =
      argc == 1 || (argc >= 2 && wcscmp(argv[1], L"session") == 0);
  if (!status && !interactive) {
    std::cerr << "usage: ProxyDomCtl.exe [session|status]\n";
    return 64;
  }

  HANDLE pipe = open_broker();
  if (pipe == INVALID_HANDLE_VALUE) {
    print_unavailable(GetLastError());
    return 2;
  }
  if (status) {
    const int code = status_once(pipe);
    CloseHandle(pipe);
    return code;
  }
  return session(pipe);
}
#endif
