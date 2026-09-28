#include "session_store.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>

#include <cstdio>
#include <cstring>
#include <vector>

#pragma comment(lib, "advapi32.lib")

namespace {

std::wstring program_data() {
  wchar_t buf[MAX_PATH] = L"C:\\ProgramData";
  const DWORD n = GetEnvironmentVariableW(L"ProgramData", buf, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return L"C:\\ProgramData";
  return buf;
}

std::wstring run_dir() { return program_data() + L"\\Proxy Dom\\run"; }

std::wstring log_dir() { return program_data() + L"\\Proxy Dom\\logs"; }

void ensure_dir(const std::wstring& path) {
  CreateDirectoryW((program_data() + L"\\Proxy Dom").c_str(), nullptr);
  CreateDirectoryW(path.c_str(), nullptr);
}

std::wstring ledger_path() { return run_dir() + L"\\ledger.txt"; }

std::wstring config_path() { return run_dir() + L"\\current_session.json"; }

std::wstring pin_path() { return run_dir() + L"\\pin.txt"; }

bool read_all(const std::wstring& path, std::string& out) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  std::string text;
  char chunk[1024];
  DWORD got = 0;
  while (ReadFile(file, chunk, sizeof(chunk), &got, nullptr) && got > 0) {
    text.append(chunk, got);
    if (text.size() > 64 * 1024) break;
  }
  CloseHandle(file);
  out = std::move(text);
  return true;
}

bool write_replace(const std::wstring& path, const std::string& text) {
  ensure_dir(run_dir());
  const std::wstring temp = path + L".tmp";
  HANDLE file = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const BOOL ok = WriteFile(file, text.data(), static_cast<DWORD>(text.size()), &written, nullptr);
  FlushFileBuffers(file);
  CloseHandle(file);
  if (!ok || written != text.size()) {
    DeleteFileW(temp.c_str());
    return false;
  }
  if (!MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    DeleteFileW(temp.c_str());
    return false;
  }
  return true;
}

std::string between_newlines(const std::string& text, const std::string& key) {
  const std::string prefix = key + "=";
  auto at = text.find(prefix);
  if (at == std::string::npos) return {};
  at += prefix.size();
  auto end = text.find('\n', at);
  if (end == std::string::npos) end = text.size();
  return text.substr(at, end - at);
}

bool looks_ipv4(const std::string& text) {
  int dots = 0;
  if (text.empty() || text.size() > 15) return false;
  for (char c : text) {
    if (c == '.') {
      ++dots;
      continue;
    }
    if (c < '0' || c > '9') return false;
  }
  return dots == 3;
}

}  // namespace

std::wstring proxy_dom_engine_config_path() {
  wchar_t buf[MAX_PATH] = L"C:\\ProgramData";
  const DWORD n = GetEnvironmentVariableW(L"ProgramData", buf, MAX_PATH);
  const std::wstring root = (n == 0 || n >= MAX_PATH) ? L"C:\\ProgramData" : buf;
  return root + L"\\Proxy Dom\\run\\current_session.json";
}

int Win32SessionFiles::load(Ledger& ledger) {
  std::string text;
  if (!read_all(ledger_path(), text)) return 0;
  if (decode_ledger(text, ledger)) return 1;
  Ledger partial;
  const std::string destination = between_newlines(text, "destination");
  MoveFileExW(ledger_path().c_str(), (run_dir() + L"\\ledger.bad").c_str(), MOVEFILE_REPLACE_EXISTING);
  if (!looks_ipv4(destination)) return -1;
  partial.pin_intended = true;
  partial.pin.destination = destination;
  partial.phase = TunnelPhase::Disconnecting;
  partial.cleanup_verified = false;
  ledger = partial;
  return 1;
}

bool Win32SessionFiles::store(const Ledger& ledger) { return write_replace(ledger_path(), encode_ledger(ledger)); }

bool Win32SessionFiles::clear() { return DeleteFileW(ledger_path().c_str()) || GetLastError() == ERROR_FILE_NOT_FOUND; }

bool Win32SessionFiles::write_config(const std::string& json) {
  ensure_dir(run_dir());
  PSECURITY_DESCRIPTOR sd = nullptr;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(L"D:P(A;;FA;;;SY)(A;;FA;;;BA)", SDDL_REVISION_1, &sd,
                                                            nullptr)) {
    return false;
  }
  SECURITY_ATTRIBUTES sa{};
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = sd;
  HANDLE file = CreateFileW(config_path().c_str(), GENERIC_WRITE, 0, &sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                            nullptr);
  LocalFree(sd);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const BOOL ok = WriteFile(file, json.data(), static_cast<DWORD>(json.size()), &written, nullptr);
  CloseHandle(file);
  return ok && written == json.size();
}

bool Win32SessionFiles::erase_config() {
  const std::wstring path = config_path();
  WIN32_FILE_ATTRIBUTE_DATA info{};
  if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &info)) {
    return GetLastError() == ERROR_FILE_NOT_FOUND;
  }
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  const DWORD bytes = info.nFileSizeLow == 0 ? 1 : info.nFileSizeLow;
  std::vector<char> zeros(bytes, '\0');
  DWORD written = 0;
  const BOOL wiped = WriteFile(file, zeros.data(), static_cast<DWORD>(zeros.size()), &written, nullptr);
  CloseHandle(file);
  if (!wiped) return false;
  return DeleteFileW(path.c_str()) == TRUE;
}

bool Win32SessionFiles::config_present() {
  const DWORD attr = GetFileAttributesW(config_path().c_str());
  return attr != INVALID_FILE_ATTRIBUTES;
}

std::string Win32SessionFiles::legacy_pin() {
  std::string text;
  if (!read_all(pin_path(), text)) return {};
  const auto end = text.find('\n');
  if (end != std::string::npos) text.resize(end);
  if (!text.empty() && text.back() == '\r') text.pop_back();
  return looks_ipv4(text) ? text : std::string{};
}

void Win32SessionFiles::clear_legacy_pin() { DeleteFileW(pin_path().c_str()); }

void Win32TunnelLog::write(std::int64_t generation,
                           const std::string& event,
                           const std::string& code,
                           unsigned long win32) {
  ensure_dir(log_dir());
  const std::wstring path = log_dir() + L"\\service.log";
  WIN32_FILE_ATTRIBUTE_DATA info{};
  if (GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &info) && info.nFileSizeLow > 1024 * 1024) {
    MoveFileExW(path.c_str(), (log_dir() + L"\\service.log.1").c_str(), MOVEFILE_REPLACE_EXISTING);
  }
  SYSTEMTIME now{};
  GetSystemTime(&now);
  char line[512];
  std::snprintf(line, sizeof(line),
                "%04u-%02u-%02uT%02u:%02u:%02uZ generation=%lld event=%s code=%s win32=%lu\r\n",
                now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
                static_cast<long long>(generation), event.c_str(), code.empty() ? "-" : code.c_str(), win32);
  HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr, OPEN_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  WriteFile(file, line, static_cast<DWORD>(std::strlen(line)), &written, nullptr);
  CloseHandle(file);
}
