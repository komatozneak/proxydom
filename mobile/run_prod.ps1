# Prod smoke on a physical Android device (VPS backend). Run: .\run_prod.ps1
Set-Location $PSScriptRoot
flutter run --dart-define=APP_ENV=prod
