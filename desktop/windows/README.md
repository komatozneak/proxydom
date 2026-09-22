# Teremok VPN for Windows (ADR 023)

Public install file is **`Teremok VPN 0.4.26.msi`** (WiX, standard Windows installer).
That is what the site and the in-app update offer. Explorer shows the generic MSI icon;
the house icon is on the **Теремок VPN** shortcut after install.

The Burn EXE (`TeremokVPN-0.4.26.exe`) is a local wizard only. Do not publish it:
SmartScreen treats the unsigned EXE as a threat.

Do **not** run `TeremokConnect.VpnService.exe` by hand. Do **not** pass `--console`.

```powershell
cd desktop/windows/dotnet
.\scripts\fetch-bins.ps1
dotnet test TeremokConnect.slnx -c Release
.\scripts\package-msi.ps1
```

The script writes `artifacts\msi\TeremokConnect-0.4.26.msi` and copies the EXE to `C:\TeremokMsi`.
Ship the MSI. Launch installers from `C:`, not from a mapped `Z:\` drive.

Only the subscription owner can remove other devices. A member can leave.

Bins (`hysteria.exe`, `wintun.dll`) are fetched, not committed. Pins: `SHA256SUMS`.
