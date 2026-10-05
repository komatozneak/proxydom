#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Centre the window on the primary monitor and open it at the size the
  // desktop layout is drawn for: the rail plus the home column.
  HMONITOR monitor = MonitorFromPoint({}, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(monitor_info);
  // Size and Point are unsigned: every value here is already non-negative.
  //
  // 826x591 is what the owner sees as a sensible window (owner call, 2026-10):
  // the old 1160x820 left the house floating in a half-empty frame and pushed
  // the app past the edge of a laptop screen. The floor below only matters on a
  // very small work area; the work-area clamp keeps the window on screen.
  constexpr unsigned int kMinWidth = 720;
  constexpr unsigned int kMinHeight = 520;
  Win32Window::Point origin(80, 60);
  Win32Window::Size size(826, 591);
  if (monitor != nullptr && GetMonitorInfo(monitor, &monitor_info)) {
    const unsigned int work_width = static_cast<unsigned int>(
        monitor_info.rcWork.right - monitor_info.rcWork.left);
    const unsigned int work_height = static_cast<unsigned int>(
        monitor_info.rcWork.bottom - monitor_info.rcWork.top);
    // windows.h defines min/max as macros, so std::min is not usable here.
    unsigned int width = work_width > 80 ? work_width - 80 : kMinWidth;
    if (width < kMinWidth) width = kMinWidth;
    if (width > size.width) width = size.width;
    unsigned int height = work_height > 80 ? work_height - 80 : kMinHeight;
    if (height < kMinHeight) height = kMinHeight;
    if (height > size.height) height = size.height;
    size = Win32Window::Size(width, height);
    origin.x = monitor_info.rcWork.left + (work_width - width) / 2;
    origin.y = monitor_info.rcWork.top + (work_height - height) / 2;
  }
  if (!window.Create(L"Proxy Dom", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
