#include "process_host.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>

#include <vector>

struct Win32Engine::Impl {
  std::wstring exe;
  std::wstring config;
  HANDLE process = nullptr;
  HANDLE thread = nullptr;
  HANDLE job = nullptr;
  DWORD pid = 0;
  DWORD last_error = 0;
};

namespace {

bool same_path(const std::wstring& left, const std::wstring& right) {
  return CompareStringOrdinal(left.c_str(), -1, right.c_str(), -1, TRUE) == CSTR_EQUAL;
}

std::wstring full_path(const std::wstring& path) {
  wchar_t full[MAX_PATH] = {};
  if (GetFullPathNameW(path.c_str(), MAX_PATH, full, nullptr) == 0) return path;
  return full;
}

}  // namespace

Win32Engine::Win32Engine(std::wstring exe, std::wstring config) : impl_(new Impl) {
  impl_->exe = std::move(exe);
  impl_->config = std::move(config);
}

Win32Engine::~Win32Engine() {
  release();
  delete impl_;
}

bool Win32Engine::launch_suspended(unsigned long& pid) {
  if (GetFileAttributesW(impl_->exe.c_str()) == INVALID_FILE_ATTRIBUTES) {
    impl_->last_error = GetLastError();
    return false;
  }
  std::wstring command = L"\"" + impl_->exe + L"\" run -c \"" + impl_->config + L"\"";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESHOWWINDOW;
  startup.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION info{};
  std::vector<wchar_t> mutable_command(command.begin(), command.end());
  mutable_command.push_back(L'\0');
  const std::wstring work = impl_->exe.substr(0, impl_->exe.find_last_of(L"\\/"));
  // Suspended until the job owns it. Break away from the SCM job when Windows allows it.
  const DWORD base = CREATE_NO_WINDOW | CREATE_SUSPENDED | CREATE_NEW_PROCESS_GROUP;
  if (!CreateProcessW(impl_->exe.c_str(), mutable_command.data(), nullptr, nullptr, FALSE,
                      base | CREATE_BREAKAWAY_FROM_JOB, nullptr, work.c_str(), &startup, &info)) {
    if (GetLastError() != ERROR_ACCESS_DENIED ||
        !CreateProcessW(impl_->exe.c_str(), mutable_command.data(), nullptr, nullptr, FALSE, base, nullptr,
                        work.c_str(), &startup, &info)) {
      impl_->last_error = GetLastError();
      return false;
    }
  }
  impl_->process = info.hProcess;
  impl_->thread = info.hThread;
  impl_->pid = info.dwProcessId;
  pid = info.dwProcessId;
  impl_->last_error = 0;
  return true;
}

bool Win32Engine::assign_job() {
  if (impl_->process == nullptr) {
    impl_->last_error = ERROR_INVALID_HANDLE;
    return false;
  }
  impl_->job = CreateJobObjectW(nullptr, nullptr);
  if (impl_->job == nullptr) {
    impl_->last_error = GetLastError();
    return false;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION info{};
  info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(impl_->job, JobObjectExtendedLimitInformation, &info, sizeof(info))) {
    impl_->last_error = GetLastError();
    return false;
  }
  if (!AssignProcessToJobObject(impl_->job, impl_->process)) {
    impl_->last_error = GetLastError();
    return false;
  }
  impl_->last_error = 0;
  return true;
}

bool Win32Engine::resume() {
  if (impl_->thread == nullptr) {
    impl_->last_error = ERROR_INVALID_HANDLE;
    return false;
  }
  if (ResumeThread(impl_->thread) == static_cast<DWORD>(-1)) {
    impl_->last_error = GetLastError();
    return false;
  }
  CloseHandle(impl_->thread);
  impl_->thread = nullptr;
  impl_->last_error = 0;
  return true;
}

bool Win32Engine::request_stop() {
  if (impl_->pid == 0) return false;
  // CREATE_NO_WINDOW has no console, so this fails closed and the supervisor kills the job.
  if (!AttachConsole(impl_->pid)) {
    impl_->last_error = GetLastError();
    return false;
  }
  SetConsoleCtrlHandler(nullptr, TRUE);
  const BOOL ok = GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, impl_->pid);
  FreeConsole();
  if (!ok) impl_->last_error = GetLastError();
  return ok == TRUE;
}

bool Win32Engine::alive() {
  if (impl_->process == nullptr) return false;
  return WaitForSingleObject(impl_->process, 0) == WAIT_TIMEOUT;
}

void Win32Engine::kill() {
  if (impl_->process == nullptr) return;
  if (!TerminateProcess(impl_->process, 0)) impl_->last_error = GetLastError();
}

void Win32Engine::release() {
  if (impl_->thread != nullptr) {
    CloseHandle(impl_->thread);
    impl_->thread = nullptr;
  }
  if (impl_->process != nullptr) {
    CloseHandle(impl_->process);
    impl_->process = nullptr;
  }
  if (impl_->job != nullptr) {
    CloseHandle(impl_->job);
    impl_->job = nullptr;
  }
  impl_->pid = 0;
}

void Win32Engine::stop_owned_processes() {
  const std::wstring mine = full_path(impl_->exe);
  HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap == INVALID_HANDLE_VALUE) {
    impl_->last_error = GetLastError();
    return;
  }
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  if (Process32FirstW(snap, &entry)) {
    do {
      if (_wcsicmp(entry.szExeFile, L"sing-box.exe") != 0) continue;
      HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_TERMINATE | SYNCHRONIZE,
                                   FALSE, entry.th32ProcessID);
      if (process == nullptr) continue;
      wchar_t image[MAX_PATH] = {};
      DWORD size = MAX_PATH;
      const BOOL named = QueryFullProcessImageNameW(process, 0, image, &size);
      if (named && same_path(full_path(image), mine)) {
        TerminateProcess(process, 0);
        WaitForSingleObject(process, 1000);
      }
      CloseHandle(process);
    } while (Process32NextW(snap, &entry));
  }
  CloseHandle(snap);
}

unsigned long Win32Engine::last_error() const { return impl_->last_error; }

void Win32Sleeper::sleep_ms(int ms) {
  if (ms > 0) Sleep(static_cast<DWORD>(ms));
}
