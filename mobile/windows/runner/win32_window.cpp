#include "win32_window.h"

#include <windowsx.h>

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// Smallest frame the desktop layout stays honest in. The window opens at
// 826x591 (main.cpp) and is not resizable by hand, so this only bounds the
// system-driven sizes: snap layouts, Aero shake and maximize. It tracks the
// opening size rather than the old 940x640 floor, which used to push the window
// back up to a frame the owner had already called too wide.
constexpr int kMinWindowWidth = 720;
constexpr int kMinWindowHeight = 520;

// The window frame is fixed: there is no resize grab band. It used to be the
// system frame (SM_CXSIZEFRAME + SM_CXPADDEDBORDER, about 16 physical px at
// 100% DPI), but WM_NCCALCSIZE below gives the entire window to the client
// area, so that band was drawn *inside* the Flutter view — which is exactly
// where the desktop scrollbar lives: MaterialScrollBehavior attaches a
// scrollbar flush to the trailing edge of every scroll view on Windows. The
// whole 15 px thumb fell inside HTRIGHT, so pressing the log scrollbar resized
// the window instead of scrolling. Fixed by owner decision (2026-10-04), so
// the band is gone entirely and the window edge belongs to the app.
//
// WS_THICKFRAME stays on the window style on purpose: it is what DWM uses to
// draw the drop shadow and what keeps the snap layouts and Aero peek working.
// Only the hit test changed — the frame is drawn and owned by Flutter, so the
// OS is never offered a chance to resize it by hand.

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  // Maximizable, but not resizable by hand: the frame is fixed at the size
  // main.cpp asks for and only the layout below, maximize, and moving it change
  // that. A draggable edge would otherwise sit on top of the desktop scrollbar,
  // which lives flush against the trailing edge of every scroll view.
  //
  // No system caption: Flutter draws it. WS_THICKFRAME stays on the style for
  // the drop shadow and the Aero snap layouts even though the hit test refuses
  // every edge, and WM_NCCALCSIZE below gives the whole window to the client
  // area — without that the invisible system frame would still steal the top
  // 30px the lockup is drawn into.
  constexpr DWORD kFixedWindowStyle =
      WS_POPUP | WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
  HWND window = CreateWindow(
      window_class, title.c_str(), kFixedWindowStyle,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_NCCALCSIZE: {
      // wParam is TRUE when the window is being resized; returning 0 there makes
      // the client area cover the entire window including what would have been
      // the caption.
      //
      // The cost of that: DefWindowProc's own hit test now sees no frame at all
      // and answers HTCLIENT everywhere, so the resize border and the snap
      // layout have to be answered by hand in WM_NCHITTEST below. They are.
      if (wparam == TRUE) {
        return 0;
      }
      break;
    }

    case WM_NCHITTEST: {
      if (caption_height_ <= 0) {
        break;
      }
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(hwnd, &point);

      // No resize band on purpose, see kMinWindowWidth above: every edge,
      // corners included, answers HTCLIENT so the engine gets the press. That
      // is what lets the scrollbar — which sits flush against the trailing
      // edge of every scroll view on desktop — be grabbed instead of turning
      // into a window drag. The frame is fixed at the size Create() opened it
      // and is only ever changed by the layout below, by maximize, or by
      // moving it.
      if (point.y < caption_height_) {
        // The buttons are ours to click, so they must not start a drag.
        if (PtInRect(&caption_buttons_, point)) {
          return HTCLIENT;
        }
        // The caption itself. Returning HTCAPTION is what gives the window its
        // drag, its double-click-to-maximize and its snap layouts back.
        return HTCAPTION;
      }
      break;
    }

    case kSetCaptionHitTestRectMsg: {
      caption_height_ = static_cast<LONG>(wparam);
      caption_buttons_ = *reinterpret_cast<RECT*>(lparam);
      return 0;
    }

    case WM_GETMINMAXINFO: {
      // Floor for the sizes Windows picks on its own (snap, shake, maximize);
      // see kMinWindowWidth above.
      MINMAXINFO* info = reinterpret_cast<MINMAXINFO*>(lparam);
      HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
      double scale = dpi / 96.0;
      info->ptMinTrackSize.x = static_cast<LONG>(Scale(kMinWindowWidth, scale));
      info->ptMinTrackSize.y = static_cast<LONG>(Scale(kMinWindowHeight, scale));

      // With no non-client area, the system's idea of "maximized" is the whole
      // monitor — taskbar included. The work area is the honest answer, and it
      // is also what makes maximize land on the right monitor of a multi-monitor
      // set rather than on the primary one.
      MONITORINFO monitor_info = {};
      monitor_info.cbSize = sizeof(monitor_info);
      if (monitor != nullptr && GetMonitorInfo(monitor, &monitor_info)) {
        const RECT& work = monitor_info.rcWork;
        const RECT& full = monitor_info.rcMonitor;
        info->ptMaxPosition.x = work.left - full.left;
        info->ptMaxPosition.y = work.top - full.top;
        info->ptMaxSize.x = work.right - work.left;
        info->ptMaxSize.y = work.bottom - work.top;
      }
      return 0;
    }

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

void Win32Window::SetCaptionRegion(LONG height, const RECT& buttons) {
  caption_height_ = height;
  caption_buttons_ = buttons;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
