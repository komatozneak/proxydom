# Prod smoke на физическом Android (VPS backend). Запуск: .\run_prod.ps1
# Anonymous UUID auth by default (skip Flash Call). Phone: -AuthAnonymous:$false
param(
  [bool]$AuthAnonymous = $true
)
Set-Location $PSScriptRoot
$anon = if ($AuthAnonymous) { 'true' } else { 'false' }
flutter run --dart-define=APP_ENV=prod --dart-define=AUTH_ANONYMOUS=$anon
