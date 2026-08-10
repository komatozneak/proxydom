# android/app/libs

Download `libXray.aar` via:

```text
mobile/scripts/fetch-libxray.ps1   # Windows
mobile/scripts/fetch-libxray.sh    # Unix
```

**Default pin: 26.6.27.** Required by `build.gradle.kts` `implementation(files(...))`.

Do not bump `LIBXRAY_VERSION` past 26.6.27 without Marzban/VPS Xray lockstep +
owner go (Reality handshake failures on 26.7+). See ADR 005.

Download `trusttunnel-client-android.aar` via:

```text
$env:GPR_KEY = (gh auth token)   # needs read:packages
mobile/scripts/fetch-trusttunnel-aar.ps1
```

**Default pin: 1.1.5-rc.2** (ADR 006 dual-core). Binary is gitignored.

**Do not** place `libbox.aar` here — sing-box runtime removed (ADR 005).
