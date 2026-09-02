# Teremok Connect for Windows (ADR 023)

Visible installer → one window → Connect (Hysteria2 TUN).
Start Menu shortcut always; desktop shortcut is a wizard checkbox (on by default).

Do **not** run `TeremokConnect.VpnService.exe` by hand. Do **not** pass `--console`.
Install the MSI wizard; the service starts as LocalSystem.

```powershell
cd desktop/windows/dotnet
.\scripts\fetch-bins.ps1
dotnet test TeremokConnect.slnx -c Release
.\scripts\package-msi.ps1
```

Then double-click the MSI **from `C:\TeremokMsi` or the Desktop copy** (not from a mapped `Z:\` drive — Windows Installer error 1620). Uninstall from Apps is allowed while
Connected. Hiddify on this PC: only Disconnect while testing Teremok; do not uninstall it.

Bins (`hysteria.exe`, `wintun.dll`) are fetched, not committed. Pins: `SHA256SUMS`.
