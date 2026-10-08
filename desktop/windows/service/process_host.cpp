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
  HANDLE read_pipe = nullptr;
  HANDLE write_pipe = nullptr;
  std::string tail;
  const char* stage = "";
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

std::wstring exe_file_name(const std::wstring& path) {
  const auto slash = path.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return path;
  return path.substr(slash + 1);
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

void Win32Engine::drain_output() const {
  if (impl_->read_pipe == nullptr) return;
  for (;;) {
    DWORD avail = 0;
    if (!PeekNamedPipe(impl_->read_pipe, nullptr, 0, nullptr, &avail, nullptr) || avail == 0) return;
    char buf[512];
    DWORD got = 0;
    const DWORD want = avail > sizeof(buf) ? sizeof(buf) : avail;
    if (!ReadFile(impl_->read_pipe, buf, want, &got, nullptr) || got == 0) return;
    impl_->tail.append(buf, got);
    if (impl_->tail.size() > 4096) impl_->tail.erase(0, impl_->tail.size() - 4096);
  }
}

bool Win32Engine::launch_suspended(unsigned long& pid) {
  if (impl_->read_pipe != nullptr) {
    CloseHandle(impl_->read_pipe);
    impl_->read_pipe = nullptr;
  }
  if (impl_->write_pipe != nullptr) {
    CloseHandle(impl_->write_pipe);
    impl_->write_pipe = nullptr;
  }
  impl_->tail.clear();
  impl_->stage = "";
  if (GetFileAttributesW(impl_->exe.c_str()) == INVALID_FILE_ATTRIBUTES) {
    impl_->last_error = GetLastError();
    impl_->stage = "core_create_process_failed";
    return false;
  }
  SECURITY_ATTRIBUTES inherit{};
  inherit.nLength = sizeof(inherit);
  inherit.bInheritHandle = TRUE;
  HANDLE read_pipe = nullptr;
  HANDLE write_pipe = nullptr;
  if (!CreatePipe(&read_pipe, &write_pipe, &inherit, 65536)) {
    impl_->last_error = GetLastError();
    impl_->stage = "core_pipe_failed";
    return false;
  }
  SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(write_pipe, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
  HANDLE nul = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &inherit, OPEN_EXISTING,
                           FILE_ATTRIBUTE_NORMAL, nullptr);
  if (nul == INVALID_HANDLE_VALUE) {
    impl_->last_error = GetLastError();
    impl_->stage = "core_pipe_failed";
    CloseHandle(read_pipe);
    CloseHandle(write_pipe);
    return false;
  }
  SetHandleInformation(nul, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);

  SIZE_T attr_size = 0;
  InitializeProcThreadAttributeList(nullptr, 1, 0, &attr_size);
  auto* attrs = static_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(HeapAlloc(GetProcessHeap(), 0, attr_size));
  if (attrs == nullptr || !InitializeProcThreadAttributeList(attrs, 1, 0, &attr_size)) {
    impl_->last_error = GetLastError();
    impl_->stage = "core_attributes_failed";
    if (attrs != nullptr) HeapFree(GetProcessHeap(), 0, attrs);
    CloseHandle(nul);
    CloseHandle(read_pipe);
    CloseHandle(write_pipe);
    return false;
  }
  HANDLE listed[] = {nul, write_pipe};
  const BOOL listed_ok = UpdateProcThreadAttribute(attrs, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, listed,
                                                    sizeof(listed), nullptr, nullptr);
  if (!listed_ok) {
    impl_->last_error = GetLastError();
    impl_->stage = "core_attributes_failed";
    DeleteProcThreadAttributeList(attrs);
    HeapFree(GetProcessHeap(), 0, attrs);
    CloseHandle(nul);
    CloseHandle(read_pipe);
    CloseHandle(write_pipe);
    return false;
  }

  std::wstring command = L"\"" + impl_->exe + L"\" run -c \"" + impl_->config + L"\"";
  STARTUPINFOEXW startup{};
  startup.StartupInfo.cb = sizeof(startup);
  startup.StartupInfo.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
  startup.StartupInfo.wShowWindow = SW_HIDE;
  startup.StartupInfo.hStdInput = nul;
  startup.StartupInfo.hStdOutput = write_pipe;
  startup.StartupInfo.hStdError = write_pipe;
  startup.lpAttributeList = attrs;
  PROCESS_INFORMATION info{};
  std::vector<wchar_t> mutable_command(command.begin(), command.end());
  mutable_command.push_back(L'\0');
  const std::wstring work = impl_->exe.substr(0, impl_->exe.find_last_of(L"\\/"));
  // Only these two handles are inherited. Both already have HANDLE_FLAG_INHERIT.
  const DWORD extended = CREATE_NO_WINDOW | CREATE_SUSPENDED | CREATE_NEW_PROCESS_GROUP | EXTENDED_STARTUPINFO_PRESENT;
  BOOL created = CreateProcessW(impl_->exe.c_str(), mutable_command.data(), nullptr, nullptr, TRUE,
                                extended | CREATE_BREAKAWAY_FROM_JOB, nullptr, work.c_str(), &startup.StartupInfo,
                                &info);
  DWORD create_error = created ? 0 : GetLastError();
  if (!created && create_error == ERROR_ACCESS_DENIED) {
    created = CreateProcessW(impl_->exe.c_str(), mutable_command.data(), nullptr, nullptr, TRUE, extended, nullptr,
                             work.c_str(), &startup.StartupInfo, &info);
    if (!created) create_error = GetLastError();
  }
  DeleteProcThreadAttributeList(attrs);
  HeapFree(GetProcessHeap(), 0, attrs);
  CloseHandle(nul);
  CloseHandle(write_pipe);
  if (!created) {
    impl_->last_error = create_error == 0 ? ERROR_INVALID_PARAMETER : create_error;
    impl_->stage = "core_create_process_failed";
    CloseHandle(read_pipe);
    return false;
  }
  impl_->read_pipe = read_pipe;
  impl_->write_pipe = nullptr;
  impl_->process = info.hProcess;
  impl_->thread = info.hThread;
  impl_->pid = info.dwProcessId;
  pid = info.dwProcessId;
  impl_->last_error = 0;
  impl_->stage = "";
  return true;
}

bool Win32Engine::assign_job() {
  if (impl_->process == nullptr) {
    impl_->last_error = ERROR_INVALID_HANDLE;
    impl_->stage = "core_job_assign_failed";
    return false;
  }
  impl_->job = CreateJobObjectW(nullptr, nullptr);
  if (impl_->job == nullptr) {
    impl_->last_error = GetLastError();
    impl_->stage = "core_job_assign_failed";
    return false;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION info{};
  info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(impl_->job, JobObjectExtendedLimitInformation, &info, sizeof(info))) {
    impl_->last_error = GetLastError();
    impl_->stage = "core_job_assign_failed";
    return false;
  }
  if (!AssignProcessToJobObject(impl_->job, impl_->process)) {
    impl_->last_error = GetLastError();
    impl_->stage = "core_job_assign_failed";
    return false;
  }
  impl_->last_error = 0;
  impl_->stage = "";
  return true;
}

bool Win32Engine::resume() {
  if (impl_->thread == nullptr) {
    impl_->last_error = ERROR_INVALID_HANDLE;
    impl_->stage = "core_resume_failed";
    return false;
  }
  if (ResumeThread(impl_->thread) == static_cast<DWORD>(-1)) {
    impl_->last_error = GetLastError();
    impl_->stage = "core_resume_failed";
    return false;
  }
  CloseHandle(impl_->thread);
  impl_->thread = nullptr;
  impl_->last_error = 0;
  impl_->stage = "";
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
  drain_output();
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
  if (impl_->read_pipe != nullptr) {
    CloseHandle(impl_->read_pipe);
    impl_->read_pipe = nullptr;
  }
  impl_->pid = 0;
}

unsigned long Win32Engine::exit_code() const {
  drain_output();
  if (impl_->process == nullptr) return impl_->last_error;
  DWORD code = 0;
  if (!GetExitCodeProcess(impl_->process, &code)) return GetLastError();
  return code;
}

std::string Win32Engine::output_tail() const {
  drain_output();
  return impl_->tail;
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
      // The image name is the file we were given, not a hardcoded sing-box.exe.
      // A sweep that still looks for the old name would leave this process up.
      const std::wstring image = exe_file_name(impl_->exe);
      if (image.empty() || _wcsicmp(entry.szExeFile, image.c_str()) != 0) continue;
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

const char* Win32Engine::start_stage() const { return impl_->stage == nullptr ? "" : impl_->stage; }

void Win32Sleeper::sleep_ms(int ms) {
  if (ms > 0) Sleep(static_cast<DWORD>(ms));
}
