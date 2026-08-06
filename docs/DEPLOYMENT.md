# Windows Deployment and Operation

## Delivery Model

The supported client package is Windows x64. FastAPI serves the compiled
Flutter dashboard, so the client installs one application and opens it from a
shortcut. Python, uv, Flutter, Git, and a terminal are build-time tools only.

PyInstaller produces a one-directory application. Inno Setup installs that
whole directory and adds a private-network firewall rule. PyInstaller does not
cross-compile: a macOS build cannot produce the final Windows executable.

## Supported Runtime

- Windows 10 or 11 x64;
- modern default browser;
- BrainAccess MINI;
- BrainAccess USB BLE adapter;
- Microsoft Visual C++ Redistributable x64;
- VR headset and operator computer on the same private LAN;
- inbound private-network access for `PanelVR.exe`.

The BrainAccess USB adapter is the validated connection path for this project.
Older integrated laptop Bluetooth adapters previously caused streams to stop
after a short period even though the sensor LED remained connected. If the
machine has integrated Bluetooth, disable it when necessary so the SDK uses the
USB adapter consistently.

## Build Inputs

The release source must contain:

- matching versions in `VERSION`, `backend/pyproject.toml`, and
  `frontend/pubspec.yaml`;
- BrainAccess native libraries under `backend/brainaccess/lib`;
- an up-to-date generated dashboard under `backend/static/web`;
- a clean committed worktree for production;
- confirmed legal permission to redistribute BrainAccess SDK DLLs.

Signing is optional for internal acceptance builds. Production delivery should
use an Authenticode code-signing certificate to reduce SmartScreen warnings and
prove artifact origin.

## GitHub Actions Release

The easiest reproducible Windows build uses
`.github/workflows/windows-release.yml`.

1. Push the intended commit to GitHub.
2. Open the repository's **Actions** tab.
3. Select **Build Windows Release**.
4. Select **Run workflow**.
5. Choose the exact branch containing the release.
6. Set **Confirm that BrainAccess DLL redistribution has been reviewed**.
7. Enable signing only when the signing secrets are configured.
8. Start the workflow and wait for **Windows x64 package** to pass.
9. Open the completed run and download
   `PanelVR-<version>-windows-x64`.

The workflow pins Windows tooling, Flutter, Python, uv, and Inno Setup; runs the
complete build and verification pipeline; and retains the artifact for 14 days.
On failure it uploads available PyInstaller and bundle diagnostics for seven
days.

### Supabase Secrets

Configure these repository Actions secrets before the first release:

- `VRDASH_SUPABASE_URL`;
- `VRDASH_SUPABASE_SERVICE_ROLE_KEY`;
- `VRDASH_SUPABASE_BUCKET`.

The workflow creates the ignored backend `.env` file during the Windows build.
The build copies it beside `PanelVR.exe`, so both the installer and portable ZIP
start with Supabase upload configured.

### GitHub Signing Secrets

Configure repository Actions secrets:

- `WINDOWS_CODESIGN_PFX_BASE64`: Base64-encoded PFX bytes;
- `WINDOWS_CODESIGN_PFX_PASSWORD`: PFX password.

The workflow imports a code-signing certificate with a private key into the
temporary runner, signs the package executable and installer, verifies the
signature, and removes the certificate at the end.

Do not enable the signing input without both secrets.

## Local Windows Release

Install:

- Git;
- Flutter and Dart on `PATH`;
- uv on `PATH`;
- Inno Setup 6 with `ISCC.exe`;
- Windows 10 SDK when signing.

Unsigned:

```powershell
.\scripts\build_release.ps1 -ConfirmBrainAccessRedistribution
```

Signed:

```powershell
.\scripts\build_release.ps1 `
  -ConfirmBrainAccessRedistribution `
  -CertificateThumbprint "CERTIFICATE_SHA1_THUMBPRINT"
```

The thumbprint belongs to a code-signing certificate installed in the current
Windows certificate store with its private key. It is not a value supplied by
this project.

The pipeline:

1. validates Windows x64, tools, versions, native DLLs, redistribution
   confirmation, and worktree state;
2. builds and verifies Flutter;
3. runs backend tests;
4. builds and verifies the PyInstaller one-directory package;
5. starts the frozen server in mock mode for an API/session/export smoke test;
6. optionally signs `PanelVR.exe`;
7. compiles the Inno Setup installer;
8. optionally signs the installer;
9. creates and verifies a portable ZIP;
10. writes release metadata and SHA-256 checksums.

Results:

```text
release/<version>/
  PanelVR-Setup-<version>-win-x64.exe
  PanelVR-<version>-win-x64.zip
  release-manifest.json
  SHA256SUMS.txt
```

The portable ZIP is useful for controlled testing. Extract the complete
`PanelVR` directory before running it. `PanelVR.exe` is not standalone.

## Client Installation

1. Install the Microsoft Visual C++ Redistributable x64 if it is not already
   present.
2. Connect the BrainAccess USB BLE adapter.
3. If needed, disable the integrated Bluetooth adapter in Windows Device
   Manager.
4. Run `PanelVR-Setup-<version>-win-x64.exe` as an administrator.
5. Accept the installer language and destination.
6. Allow Windows Firewall access on private networks. The installer normally
   creates this rule automatically.
7. Start **Panel VR** from the Start menu.

The installer puts program files in:

```text
%ProgramFiles%\NEXT\Panel VR
```

It creates a private-profile inbound firewall rule named `Panel VR` for the
installed executable. Uninstall removes program files and that rule, but
preserves session data.

## Device Startup Sequence

1. Connect the USB BLE adapter.
2. Ensure the sensor has sufficient battery and is not connected for charging.
3. Close BrainAccess Board and other BrainAccess applications.
4. Connect the computer and VR headset to the same private Wi-Fi/LAN.
5. Start Panel VR and wait for the browser dashboard.
6. Start the VR application.
7. Verify activity before creating a session.

The setup screen indicators mean:

- **Backend**: dashboard WebSocket is connected;
- **EEG**: a sample arrived within the last three seconds;
- **VR**: a preview frame arrived within the last three seconds;
- **ET**, where shown: a valid eye-tracking message arrived within three
  seconds.

These are live-activity indicators, not only hardware pairing indicators. A
steady sensor LED without fresh EEG values is not enough.

The EEG row also contains a switch. Turn it off before creating a session when
EEG is intentionally not used. The backend then stops acquisition, device
discovery, and five-second reconnect attempts. Turn it on to start discovery
again. The setting is locked for the duration of an active session.

## Acceptance Test

Perform this on the actual client laptop, sensor, adapter, network, and headset.

### Application

1. Start from the installed shortcut without a terminal.
2. Confirm the browser opens `http://127.0.0.1:8080`.
3. Open `http://127.0.0.1:8080/api/health` and verify `status` is `ok`.
4. Confirm the version matches the delivered release.

### EEG

1. Confirm `eeg_mode` is `real`.
2. Wait for `eeg_status` to become `streaming`.
3. Confirm all eight plots update continuously for at least 10 minutes.
4. Move or briefly touch an electrode only as permitted by the test procedure
   and verify the raw trace changes.
5. Confirm no `eeg_error` appears.

### VR and ET

1. Confirm the headset discovers the server without entering an IP address.
2. Confirm the preview updates continuously.
3. Confirm dashboard scene/action controls affect Unity.
4. Confirm gaze points move through the preview and disappear when Unity cannot
   produce a valid screen projection.

### Session

1. Create a test session with a non-patient identifier.
2. Record at least five minutes of EEG, ET, and VR traffic.
3. Add predefined and custom observations.
4. End the session.
5. Confirm nonzero expected counts and `dropped_records: 0`.
6. Download both summary JSON and raw ZIP.
7. Extract the ZIP and verify every NDJSON line parses as JSON.
8. Confirm `eeg.ndjson` contains increasing sequences/sample positions and
   sustained raw values across the session.

### Recovery

1. Start a disposable test session.
2. Terminate Panel VR without ending the session.
3. Restart the application.
4. Confirm the interrupted session summary is shown and can be exported.

## Data Locations

Runtime root:

```text
%LOCALAPPDATA%\NEXT\PanelVR
```

Important paths:

```text
logs\panel-vr.log
logs\panel-vr.log.1 ... panel-vr.log.5
sessions.sqlite3
sessions\<session_id>\...
exports\...
```

The log rotates at 5 MiB with five backups. Temporary export archives may
remain under `exports`; downloaded copies are managed by the browser.

Back up `sessions.sqlite3` and the complete `sessions` directory together. Do
not rename or edit individual NDJSON files in an active session.

## Troubleshooting

### Dashboard Does Not Open

- Start Panel VR once more; the launcher opens the existing healthy instance.
- Check whether another application uses port `8080`.
- Open `%LOCALAPPDATA%\NEXT\PanelVR\logs\panel-vr.log`.
- Try `http://127.0.0.1:8080/api/health`.

### VR Does Not Connect

- Confirm the network is marked **Private** in Windows.
- Confirm computer and headset are on the same subnet and client isolation is
  disabled.
- Confirm the `Panel VR` inbound firewall rule exists and is enabled for the
  private profile.
- Check `/api/health` for `beacon_running: true`.
- Check the log for `Beacon advertising: ws://<correct-lan-ip>:8080/ws`.
- If multiple network adapters or a VPN select the wrong address, set
  `BEACON_HOST` for a development diagnosis. A packaged production override
  requires launching with that environment configured.
- UDP discovery uses port `15000`; WebSocket traffic uses TCP `8080`.

### EEG Does Not Become Active

- Use the BrainAccess USB BLE adapter.
- Disable an unreliable integrated Bluetooth adapter.
- Confirm the configured name is `BA MINI 037` or set the correct name.
- Close BrainAccess Board; the sensor connection is exclusive.
- Disconnect charging and confirm battery state.
- Confirm Visual C++ Redistributable x64 is installed.
- Check `eeg_status` and `eeg_error` in `/api/health`.
- Inspect the log for connection, callback, stale-stream, and retry messages.

For a development machine with Python available, run:

```powershell
cd backend
uv run python eeg_diagnostic.py --device "BA MINI 037" --duration 10
```

### EEG LED Is Blue but Plots Stop

The LED represents the BLE link, not sustained sample callbacks. Verify that
`sequence`, `sample_start`, and `sample_count` continue increasing in
`eeg.ndjson`. The supported repair is to use the BrainAccess USB BLE adapter
and avoid the older integrated adapter that caused the observed stalls.

### Eye Tracking Is Missing or at Edges

- Confirm Unity sends messages with `type: eye_tracking`.
- Confirm all required transform objects are present.
- Confirm `gaze_screen_x/y` are finite normalized coordinates in `[0, 1]`.
- Do not clamp a failed camera projection to 0 or 1; omit screen coordinates.
- Verify Unity projects gaze through the same camera used to produce the
  streamed preview.

### Session Counts Are Zero

- Create the session before expecting records to persist.
- Check live activity indicators.
- Check `active_session_id` and `session_recording_error` in `/api/health`.
- Inspect the matching session NDJSON files while the session runs.
- End the session normally to drain the queue before reviewing exports.

## Upgrade and Uninstall

Installing a newer version over the existing installation replaces program
files. Session data remains in `%LOCALAPPDATA%`.

Before an upgrade:

1. end any active session;
2. export required session data;
3. back up the application data directory;
4. verify the new version in a test installation when possible.

Uninstalling does not remove patient/session data. Delete that directory only
under the organization's approved retention and deletion procedure.

## Release Evidence

Retain for each delivered version:

- source commit;
- GitHub Actions run or local build log;
- `release-manifest.json`;
- `SHA256SUMS.txt`;
- signed installer signature status, when applicable;
- BrainAccess redistribution approval;
- completed hardware acceptance record.
