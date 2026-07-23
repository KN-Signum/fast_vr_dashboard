# Windows Release Checklist

## Before building

- Use a Windows 10 or Windows 11 x64 build computer.
- Install Flutter, Git, uv, Inno Setup 6.3 or newer, and the Windows 10 SDK
  when signing.
- Confirm that the BrainAccess licence permits redistribution of
  `babciconnect.dll`, `bacore.dll`, and `simpleble.dll`.
- Use a clean Git checkout of the release commit.
- Set the version consistently through `VERSION`, `frontend/pubspec.yaml`, and
  `backend/pyproject.toml`.

## Build

Run PowerShell as an administrator:

```powershell
.\scripts\build_release.ps1 -ConfirmBrainAccessRedistribution
```

For a signed production build:

```powershell
.\scripts\build_release.ps1 `
  -ConfirmBrainAccessRedistribution `
  -CertificateThumbprint "CERTIFICATE_SHA1_THUMBPRINT"
```

Do not use `-AllowDirty` for a client release.

## Verify

- Confirm that `release\<version>` contains the installer, portable ZIP,
  `release-manifest.json`, and `SHA256SUMS.txt`.
- Run `Get-AuthenticodeSignature` on both `PanelVR.exe` and the installer when
  code signing is enabled.
- Recalculate SHA-256 hashes and compare them with `SHA256SUMS.txt`.
- Install on a separate Windows x64 computer without Python, Flutter, or uv.
- Confirm that the Start menu shortcut launches Panel VR and opens the browser.
- Confirm that Windows Firewall contains the private-network Panel VR rule.
- Confirm that uninstall removes the application but preserves
  `%LOCALAPPDATA%\NEXT\PanelVR`.

## Hardware acceptance

- Install the Microsoft Visual C++ x64 runtime required by the BrainAccess SDK.
- Pair the BrainAccess device over Bluetooth.
- Run `eeg_diagnostic.py` on the build or diagnostic environment before final
  client acceptance.
- Verify real EEG samples and status in the dashboard.
- Verify VR frames, scene commands, and eye-tracking points.
- Create and end a complete patient session.
- Verify summary and raw-data downloads.
- Review `%LOCALAPPDATA%\NEXT\PanelVR\logs\panel-vr.log` for errors.

Archive the exact installer, ZIP, checksums, release manifest, Git commit, and
hardware acceptance result delivered to the client.
