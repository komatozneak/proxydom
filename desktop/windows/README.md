# Teremok Windows Hy2 host

Thin user-mode host + **official** Hysteria2 Windows client. Not Flutter Windows.
Android CI (`.github/workflows/mobile-build.yml`) is unchanged.

| File | Source |
| --- | --- |
| `teremok-host.exe` | this module, `CGO_ENABLED=0`, `GOOS=windows GOARCH=amd64` |
| `hysteria.exe` | apernet `app/v2.6.2` `hysteria-windows-amd64.exe` (same core pin as Android `HYSTERIA_TAG=v2.6.2`) |
| `wintun.dll` | [wintun 0.14.1](https://www.wintun.net/) **amd64** only |

Binaries are **not** in git. Pins live in `SHA256SUMS`.

## Build (Linux CI or any Go 1.23+)

```bash
cd desktop/windows
go test ./...
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o dist/teremok-host.exe ./cmd/teremok-host
bash scripts/fetch-bins.sh
bash scripts/package.sh   # Linux: zip dist/teremok-windows-x64.zip
```

On this Windows machine:

```powershell
cd desktop\windows
.\scripts\fetch-bins.ps1
$env:CGO_ENABLED = "0"
go build -trimpath -ldflags="-s -w" -o .\bin\teremok-host.exe .\cmd\teremok-host
```

`go mod tidy` must be run with `GOOS=windows` so `golang.org/x/sys/windows` stays in `go.mod`.

## Smoke (Win10 x64)

SOCKS first — no UAC, prove on `:10808`:

```powershell
.\scripts\smoke-local.ps1
```

Expect log `prove egress=<ip>` equal to the Hy2 node (`node_host` / EU `217.60.3.9` or US `45.91.248.91`), not your ISP.

Then TUN (UAC prompt is **only** for `hysteria.exe`; the host stays unelevated). Click Allow:

```powershell
.\bin\teremok-host.exe -bin-dir .\bin -mode tun -prove -headless -once
```

System egress (browser / `curl.exe https://ifconfig.me/ip`, not SOCKS) should be the Hy2 node, same as SOCKS prove. Adapter name is `teremokhy2` (not leftover `hytun` / sing-tun). Logs: `bin\hysteria.log`.

If UAC is canceled, SOCKS still works; TUN will not capture the default route.

Keep a session up: omit `-once`, stop with Ctrl+C. Tray UI (no `-headless`): Connect SOCKS / Connect TUN / Disconnect.

SmartScreen: Run anyway. Do not wrap the zip in SFX/Enigma. MSI/WiX is phase 2.

## API

Anonymous `POST /v2/auth/register` (`platform=windows`) then HMAC `GET /v2/app/connect/get/v3` (path **without** query). Session: `%APPDATA%\TeremokConnect\session.json`.

Default origin: `https://api.teremokconnect.online:8443`.
