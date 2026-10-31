# Release publisher

The code repository is private. Users download only signed builds from a
separate public distribution repository; no source, build logs or symbol maps
are pushed there.

`publish-release.ps1` stages finished `.apk`, `.aab`, `.ipa`, `.msi`, `.exe` or
`.dmg` files, writes a SHA256 beside each one, adds `RELEASE.json`, commits
under `releases/<version>/`, and pushes.

```powershell
pwsh ./publish-release.ps1 `
  -Version 1.0.0 `
  -Artifacts ..\..\dist\proxydom-1.0.0.apk,..\..\dist\proxydom-1.0.0.aab,..\..\dist\proxydom-1.0.0.msi `
  -DistRepo ..\..\..\proxydom-releases `
  -DownloadBaseUrl https://dl.proxydom.su/releases/1.0.0 `
  -NotesFile ..\..\dist\RELEASE-NOTES.md
```

The script refuses:

- anything that is not a release binary extension;
- names containing `debug`, `profile`, `ci`, `symbols` or `unsigned`;
- an existing version directory;
- a dirty distribution checkout.

`RELEASE.json` is the only machine-readable input for the website and the
in-app updater; the app never calls the source repository's GitHub API.
