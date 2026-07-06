# Prod smoke на физическом Android (VPS backend). Запуск: .\run_prod.ps1
Set-Location $PSScriptRoot
flutter run --dart-define=APP_ENV=prod
