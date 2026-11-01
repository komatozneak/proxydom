#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <shellapi.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayOpen = 1;
constexpr UINT kTrayQuit = 2;

std::wstring Widen(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                       static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), size);
  return wide;
}

// The Flutter view fills the whole client area, so it — not the top-level
// window — is what the system hit-tests for mouse input. Without this the view
// answered HTCLIENT to everything and the caption could not be dragged, even
// though the top-level handler gave the right answer when asked directly.
//
// The view does not try to answer for itself: it asks its parent, which already
// knows where the caption is, where the buttons are and how wide the resize
// border is. One hit test, one place that computes it.
//
// That answer alone is not enough. When it says HTCAPTION the system believes
// it and turns the press into a non-client press — but a child window has no
// frame to move, so nothing happens. The press has to be passed on to the
// parent, which does have one. This is also what puts the resize cursors on the
// edges: they follow from the hit test, for free.
//
// Worth knowing if this is ever retested: injected input (mouse_event /
// SendInput) does not drive the move loop, so an automated drag reports failure
// even when dragging by hand works. It was verified by hand.
WNDPROC g_previous_view_proc = nullptr;

LRESULT CALLBACK ViewWndProc(HWND window, UINT message, WPARAM wparam,
                             LPARAM lparam) {
  HWND parent = GetParent(window);
  if (parent != nullptr) {
    if (message == WM_NCHITTEST) {
      return SendMessage(parent, message, wparam, lparam);
    }
    if (message == WM_NCLBUTTONDOWN || message == WM_NCLBUTTONDBLCLK) {
      // Release the capture first: the parent's own handler takes it, and a
      // capture held by the child would starve it of the moves.
      ReleaseCapture();
      return SendMessage(parent, message, wparam, lparam);
    }
  }
  return CallWindowProc(g_previous_view_proc, window, message, wparam, lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetCaptionChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Subclass the view so WM_NCHITTEST reaches the handler in win32_window.cpp.
  HWND view = flutter_controller_->view()->GetNativeWindow();
  g_previous_view_proc = reinterpret_cast<WNDPROC>(
      SetWindowLongPtr(view, GWLP_WNDPROC,
                       reinterpret_cast<LONG_PTR>(ViewWndProc)));

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  caption_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// The window chrome, from the Dart side.
//
// Flutter draws the caption, so it is also the only thing that knows where the
// caption is. The buttons need three answers the frame used to give for free,
// and the native side needs the button rectangle so it can leave that corner
// out of the drag region — both directions are this one channel.
void FlutterWindow::SetCaptionChannel() {
  caption_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "proxydom/window_chrome", &flutter::StandardMethodCodec::GetInstance());

  caption_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HWND hwnd = GetHandle();
        if (hwnd == nullptr) {
          result->Error("no_window", "The window is gone.", nullptr);
          return;
        }
        const std::string& method = call.method_name();
        if (method == "minimize") {
          ShowWindow(hwnd, SW_MINIMIZE);
        } else if (method == "hideToTray") {
          const auto* args = std::get_if<flutter::EncodableMap>(
              call.arguments());
          if (args != nullptr) {
            auto text = [args](const char* key) -> std::wstring {
              auto it = args->find(flutter::EncodableValue(key));
              if (it == args->end()) return std::wstring();
              const auto* value = std::get_if<std::string>(&it->second);
              return value == nullptr ? std::wstring() : Widen(*value);
            };
            if (auto v = text("tooltip"); !v.empty()) tray_tip_ = v;
            if (auto v = text("open"); !v.empty()) tray_open_ = v;
            if (auto v = text("quit"); !v.empty()) tray_quit_ = v;
          }
          HideToTray();
        } else if (method == "toggleMaximize") {
          const bool maximized = IsZoomed(hwnd) != FALSE;
          ShowWindow(hwnd, maximized ? SW_RESTORE : SW_MAXIMIZE);
        } else if (method == "close") {
          // Post, not Send: a close that comes back through the message pump
          // would re-enter this very call stack.
          PostMessage(hwnd, WM_CLOSE, 0, 0);
        } else if (method == "isMaximized") {
          result->Success(flutter::EncodableValue(IsZoomed(hwnd) != FALSE));
          return;
        } else if (method == "setCaptionRegion") {
          const auto* args = std::get_if<flutter::EncodableMap>(
              call.arguments());
          double height = 0;
          double left = 0, top = 0, right = 0, bottom = 0;
          if (args != nullptr) {
            height = std::get<double>(args->at("height"));
            left = std::get<double>(args->at("buttonsLeft"));
            top = std::get<double>(args->at("buttonsTop"));
            right = std::get<double>(args->at("buttonsRight"));
            bottom = std::get<double>(args->at("buttonsBottom"));
          }
          // Dart lays out in logical pixels, the window works in physical ones.
          const UINT dpi = FlutterDesktopGetDpiForMonitor(
              MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY));
          const double scale = dpi / 96.0;
          RECT buttons{
              static_cast<LONG>(left * scale), static_cast<LONG>(top * scale),
              static_cast<LONG>(right * scale), static_cast<LONG>(bottom * scale)};
          SetCaptionRegion(static_cast<LONG>(height * scale), buttons);
        } else {
          result->NotImplemented();
          return;
        }
        result->Success(flutter::EncodableValue());
      });
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (taskbar_created_ == 0) {
    taskbar_created_ = RegisterWindowMessage(L"TaskbarCreated");
  }
  if (message == taskbar_created_ && tray_visible_) {
    // Explorer came back with an empty tray; put the icon back in it.
    tray_visible_ = false;
    AddTrayIcon();
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case kTrayMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          RestoreFromTray();
          return 0;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          return 0;
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

bool FlutterWindow::AddTrayIcon() {
  if (tray_visible_) return true;
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return false;
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = hwnd;
  data.uID = kTrayIconId;
  data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  data.uCallbackMessage = kTrayMessage;
  // The small size of the same .ico the window and the taskbar use.
  data.hIcon = static_cast<HICON>(LoadImage(
      GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0));
  wcsncpy_s(data.szTip, tray_tip_.c_str(), _TRUNCATE);
  tray_visible_ = Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
  if (data.hIcon != nullptr) DestroyIcon(data.hIcon);
  return tray_visible_;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_visible_) return;
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &data);
  tray_visible_ = false;
}

void FlutterWindow::HideToTray() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;
  // No icon, no way back: then the window is minimized as before instead.
  if (!AddTrayIcon()) {
    ShowWindow(hwnd, SW_MINIMIZE);
    return;
  }
  ShowWindow(hwnd, SW_HIDE);
}

void FlutterWindow::RestoreFromTray() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;
  ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(hwnd);
  RemoveTrayIcon();
}

void FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;
  AppendMenuW(menu, MF_STRING, kTrayOpen, tray_open_.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayQuit, tray_quit_.c_str());
  SetMenuDefaultItem(menu, kTrayOpen, FALSE);
  POINT cursor;
  GetCursorPos(&cursor);
  // Without the window in front the menu does not close on an outside click.
  SetForegroundWindow(hwnd);
  const UINT picked = static_cast<UINT>(TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON, cursor.x, cursor.y,
      0, hwnd, nullptr));
  PostMessage(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);
  if (picked == kTrayOpen) {
    RestoreFromTray();
  } else if (picked == kTrayQuit) {
    RemoveTrayIcon();
    PostMessage(hwnd, WM_CLOSE, 0, 0);
  }
}
