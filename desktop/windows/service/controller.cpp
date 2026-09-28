#include "protocol.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>

#include <atomic>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace {

const wchar_t* kPipeName = L"\\\\.\\pipe\\ProxyDomBrokerV3";

std::wstring exe_dir() {
  wchar_t path[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring text(path);
  const auto slash = text.find_last_of(L"\\/");
  return slash == std::wstring::npos ? L"." : text.substr(0, slash);
}

std::wstring normalize_path(const std::wstring& path) {
  wchar_t full[MAX_PATH] = {};
  if (GetFullPathNameW(path.c_str(), MAX_PATH, full, nullptr) == 0) return path;
  return full;
}

bool same_path(const std::wstring& left, const std::wstring& right) {
  return CompareStringOrdinal(normalize_path(left).c_str(), -1,
                              normalize_path(right).c_str(), -1, TRUE) ==
         CSTR_EQUAL;
}

bool process_is_local_system(HANDLE process) {
  HANDLE token = nullptr;
  if (!OpenProcessToken(process, TOKEN_QUERY, &token)) return false;
  DWORD bytes = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &bytes);
  std::vector<unsigned char> storage(bytes);
  const bool read =
      bytes != 0 &&
      GetTokenInformation(token, TokenUser, storage.data(), bytes, &bytes);
  CloseHandle(token);
  if (!read) return false;

  unsigned char local_system[SECURITY_MAX_SID_SIZE] = {};
  DWORD sid_size = sizeof(local_system);
  if (!CreateWellKnownSid(WinLocalSystemSid, nullptr, local_system, &sid_size)) {
    return false;
  }
  const auto* user = reinterpret_cast<const TOKEN_USER*>(storage.data());
  return EqualSid(user->User.Sid, local_system) == TRUE;
}

bool trusted_server(HANDLE pipe) {
  ULONG pid = 0;
  if (!GetNamedPipeServerProcessId(pipe, &pid) || pid == 0) return false;
  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) return false;
  wchar_t image[MAX_PATH] = {};
  DWORD size = MAX_PATH;
  const bool named =
      QueryFullProcessImageNameW(process, 0, image, &size) == TRUE;
  const bool trusted =
      named && process_is_local_system(process) &&
      same_path(image, exe_dir() + L"\\ProxyDomBroker.exe");
  CloseHandle(process);
  return trusted;
}

HANDLE open_broker() {
  for (int attempt = 0; attempt < 30; ++attempt) {
    HANDLE pipe =
        CreateFileW(kPipeName, FILE_READ_DATA | FILE_WRITE_DATA | READ_CONTROL | SYNCHRONIZE,
                    0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (pipe != INVALID_HANDLE_VALUE) {
      DWORD mode = PIPE_READMODE_MESSAGE;
      if (SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr) &&
          trusted_server(pipe)) {
        return pipe;
      }
      CloseHandle(pipe);
      SetLastError(ERROR_ACCESS_DENIED);
      return INVALID_HANDLE_VALUE;
    }
    const DWORD error = GetLastError();
    if (error != ERROR_PIPE_BUSY && error != ERROR_FILE_NOT_FOUND) break;
    WaitNamedPipeW(kPipeName, 100);
  }
  return INVALID_HANDLE_VALUE;
}

bool write_json(HANDLE pipe, const std::string& json) {
  const std::string frame = encode_frame(json);
  if (frame.empty()) return false;
  DWORD written = 0;
  return WriteFile(pipe, frame.data(), static_cast<DWORD>(frame.size()),
                   &written, nullptr) &&
         written == frame.size();
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
  std::atomic<bool> reading{true};
  std::thread reader([&] {
    std::string response;
    while (read_json(pipe, response)) {
      std::cout << response << std::endl;
    }
    std::cout
        << "{\"event\":\"broker_closed\",\"generation\":0,\"state\":\"\","
           "\"code\":\"broker_unavailable\",\"message\":null}"
        << std::endl;
    reading.store(false);
  });

  std::string line;
  while (reading.load() && std::getline(std::cin, line)) {
    if (line.empty()) continue;
    ClientCommand command;
    std::string error;
    if (!parse_command(line, command, error) ||
        command.protocol_version != 3) {
      std::cout
          << "{\"event\":\"client_error\",\"code\":\"protocol\","
             "\"message\":\"Некорректная команда окна\"}"
          << std::endl;
      continue;
    }
    if (!write_json(pipe, line)) break;
  }

  CancelIoEx(pipe, nullptr);
  CloseHandle(pipe);
  if (reader.joinable()) reader.join();
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
