#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include <bitsdojo_window_windows/bitsdojo_window_plugin.h>

auto bdw = bitsdojo_window_configure(BDW_CUSTOM_FRAME);

// Single-instance support. The mutex name is tied to the installer AppId so it
// is unambiguous; no "Global\\" prefix keeps it session-local (one instance per
// user session). See docs/superpowers/specs/2026-06-16-single-instance-design.md.
namespace {

constexpr const wchar_t kSingleInstanceMutexName[] =
    L"GitOpen-SingleInstance-{A2D8F37C-2D31-4F3D-99A1-7D8B6C7E2A11}";

// The window class Flutter's Win32 runner registers (see win32_window.cpp) plus
// the title set in wWinMain — together they identify our existing window.
constexpr const wchar_t kRunnerWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kRunnerWindowTitle[] = L"gitopen";

// Brings an already-running instance's window to the foreground. Retries briefly
// to cover the race where the first instance holds the mutex but has not created
// its window yet.
void SurfaceExistingWindow() {
  for (int attempt = 0; attempt < 10; ++attempt) {
    HWND existing = ::FindWindowW(kRunnerWindowClass, kRunnerWindowTitle);
    if (existing != nullptr) {
      if (::IsIconic(existing)) {
        ::ShowWindow(existing, SW_RESTORE);
      }
      ::SetForegroundWindow(existing);
      return;
    }
    ::Sleep(100);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // If another instance is already running, surface its window and exit.
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    SurfaceExistingWindow();
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

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
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"gitopen", origin, size)) {
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
