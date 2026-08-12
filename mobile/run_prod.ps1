# Prod smoke на физическом Android (VPS backend). Запуск: .\run_prod.ps1
# Anonymous UUID auth by default. Set -AuthAnonymous:$false only for legacy builds.
param(
  [bool]$AuthAnonymous = $true
)
Set-Location $PSScriptRoot
$anon = if ($AuthAnonymous) { 'true' } else { 'false' }
flutter run --dart-define=APP_ENV=prod --dart-define=AUTH_ANONYMOUS=$anon
