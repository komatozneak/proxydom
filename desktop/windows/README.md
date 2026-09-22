# Teremok VPN for Windows (ADR 023)

Visible **EXE** wizard (WiX Burn + oak/moss WPF) → one window → Connect (Hysteria2 TUN).
Start Menu shortcut always; desktop shortcut is on by default.

Do **not** run `TeremokConnect.VpnService.exe` by hand. Do **not** pass `--console`.
Install the EXE; the MSI inside starts `TeremokConnectVpn` as LocalSystem.

```powershell
cd desktop/windows/dotnet
.\scripts\fetch-bins.ps1
dotnet test TeremokConnect.slnx -c Release
.\scripts\package-msi.ps1
```

Then double-click **TeremokVPN-0.4.26.exe** from `C:\TeremokMsi` or the Desktop copy
(not from a mapped `Z:\` drive). Uninstall from Apps is allowed while Connected.
Hiddify on this PC: only Disconnect while testing Teremok; do not uninstall it.

Bins (`hysteria.exe`, `wintun.dll`) are fetched, not committed. Pins: `SHA256SUMS`.
