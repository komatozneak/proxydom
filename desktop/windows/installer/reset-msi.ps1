# Run only when an install is stuck with "another installation is in progress"
# and the installer window no longer makes progress. An orphaned transaction
# keeps the Windows Installer _MSIExecute mutex; restarting the Installer
# service clears it without a reboot.
#
# Right-click -> Run with PowerShell as administrator, or:
#   Start-Process powershell -Verb RunAs -ArgumentList '-ExecutionPolicy Bypass -File "<path>\reset-msi.ps1"'
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "Stopping orphaned msiexec clients..."
Get-Process msiexec -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

Write-Host "Restarting the Windows Installer service..."
Restart-Service msiserver -Force
Start-Sleep -Seconds 1

Get-Service msiserver | Format-Table Name, Status
Write-Host "Windows Installer reset. Start the MSI once; do not open two copies."
