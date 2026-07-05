# Changelog — Teremok Connect Mobile

## v0.2.0 — libbox JNI tun2socks (2026-07-05)

### Added
- Pre-built `libbox.aar` v1.13.14 (sing-box via gomobile, NDK 28.0.13004108)
- `SingBoxBridge` JNI binding через `CommandServer` + `PlatformInterface`
- `TunForwarder` передаёт TUN fd в libbox (`SingBoxBridge.setTunFd`)
- Build script `mobile/scripts/build-libbox.sh` + CI workflow `build-libbox-aar.yml`

### Changed
- VPN core: CLI child process → libbox native (`System.loadLibrary("box")`)
- `buildSingBoxJson`: gvisor stack, direct outbound, route.final=proxy

### Removed
- sing-box CLI binaries из `android/app/src/main/assets/` (~165 MB)

### Verification (device)
```bash
adb logcat -s SingBoxBridge:V TunForwarder:V TeremokVpn:V
# Connect → curl ifconfig.me → VPS IP
```

## v0.1.0-alpha — MVP (2026-07-03)

См. [RELEASE_NOTES_v0.1.0-alpha.md](./RELEASE_NOTES_v0.1.0-alpha.md)
