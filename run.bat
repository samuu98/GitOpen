@echo off
:: GitOpen — Windows run wrapper. Forwards args to run.ps1.
:: Usage:
::   run                  - debug run on Windows desktop
::   run build [release]  - build only
::   run test             - flutter test
::   run analyze          - flutter analyze
::   run clean            - clean + pub get
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
