#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Exposes the window chrome — caption region, minimise, maximise, close — to
  // the Dart side that draws it.
  void SetCaptionChannel();

  // The tray. The minimize button hides the window and leaves an icon by the
  // clock: a VPN keeps running when its window is put away, and the taskbar is
  // the wrong place to keep it. A click on the icon brings the window back; its
  // menu opens or quits the app. The labels come from Dart, in the app's
  // language.
  void HideToTray();
  void RestoreFromTray();
  bool AddTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();

  bool tray_visible_ = false;
  std::wstring tray_tip_ = L"Proxy Dom";
  std::wstring tray_open_ = L"Open";
  std::wstring tray_quit_ = L"Quit";

  // Explorer broadcasts this when it restarts and the tray is rebuilt empty.
  UINT taskbar_created_ = 0;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      caption_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
