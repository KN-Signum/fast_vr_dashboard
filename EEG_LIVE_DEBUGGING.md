# BrainAccess EEG Live Debugging Handoff

## Purpose

This document captures the current BrainAccess EEG problem and the evidence
needed during the next live debugging session on the Windows laptop.

Keep VR and eye tracking outside the scope of this investigation. The immediate
goal is to determine whether the EEG stream is failing inside:

1. the BrainAccess device, firmware, Bluetooth adapter, or Windows driver;
2. the BrainAccess SDK; or
3. the Panel VR SDK lifecycle and callback integration.

Do not make another production release until the official BrainAccess stream
and the Panel VR stream have both been observed for at least five minutes.

## Current Release

- Panel VR version: `0.1.2`
- Source commit: `9eafa53`
- EEG mode: `real`
- Configured device: `BA MINI 037`
- Sampling rate: 250 Hz
- Channels sent to the dashboard: `Fp1`, `Fp2`, `O1`, `O2`
- Application log:
  `%LOCALAPPDATA%\NEXT\PanelVR\logs\panel-vr.log`
- Session data:
  `%LOCALAPPDATA%\NEXT\PanelVR\sessions`
- Health endpoint:
  `http://127.0.0.1:8080/api/health`

The dashboard currently reports EEG as online only when it has received a
recent EEG payload. It does not display the backend's `eeg_status` or
`eeg_error` from `/api/health`.

## Confirmed Failure Timeline

The relevant `0.1.2` run in the supplied log occurred on 2026-07-30:

| Time | Event |
| --- | --- |
| 10:43:09 | Panel VR started connecting to `BA MINI 037`. |
| 10:43:54 | BrainAccess acquisition started successfully. |
| 10:43:55 | EEG callback data arrived; backend status became `streaming`. |
| 10:44:18 | No fresh callback data had arrived for the stale timeout. |
| 10:44:18 | Backend raised `BrainAccess sensor stopped delivering fresh EEG samples`. |
| 10:44:28 | SDK `stop_stream()` failed with `Connection error`. |
| 10:46:12 | Panel VR was started again. |
| 10:46:40 | Initial reconnect failed with `Could not connect to device Connection error`. |
| 10:46:55 onward | Repeated scans failed with `No devices found`. |

This establishes the following:

- Device discovery and initial connection can succeed.
- At least one real EEG payload reaches the backend.
- Data then stops below the WebSocket/frontend layer.
- The SDK reports that its device connection has failed.
- Automatic retries run, but the device is no longer advertising or discoverable
  to the SDK.

A solid blue device LED confirms a Bluetooth connection, but it does not prove
that EEG chunks are still being delivered to the application.

## Current Implementation Risks

These are hypotheses, not confirmed root causes:

1. `acquisition.EEG.start_acquisition()` registers the acquisition helper's
   callback and starts the stream. Panel VR replaces that callback afterward.
   The BrainAccess documentation recommends registering the chunk callback
   before starting the stream.
2. Every retry creates `acquisition.EEG`, which initializes BrainAccess Core,
   and closes the global core during cleanup. The official examples initialize
   Core once for the process and close it after all managers are finished.
3. Cleanup asks the SDK whether it is streaming even after discovery failed.
   The log contains cases where this led to `stop_stream()` being called after
   `No devices found`, followed by another `Connection error`.
4. The three-second stale timeout may be too aggressive for a temporary
   Bluetooth interruption, although the later SDK connection error confirms
   that the observed incident was more than a frontend timing issue.
5. BrainAccess native logging is not enabled, so the current application log
   cannot explain why the Bluetooth stream stopped.

## Preparation On Windows

Before testing:

1. Charge the BrainAccess device and do not charge it while streaming.
2. Record whether the laptop uses integrated Bluetooth or the supplied
   BrainAccess USB adapter.
3. Prefer the supplied USB adapter for the first controlled test.
4. Close Panel VR, BrainAccess Board, Configurator, EEG Viewer, and any other
   process that may connect to the sensor.
5. Power the sensor off for at least 15 seconds, then power it on.
6. Confirm the exact advertised name is `BA MINI 037`.
7. Note the initial LED mode and every LED change during testing.

Useful PowerShell commands during a live debugging session:

```powershell
Get-Content "$env:LOCALAPPDATA\NEXT\PanelVR\logs\panel-vr.log" -Wait
```

```powershell
Invoke-RestMethod http://127.0.0.1:8080/api/health |
  ConvertTo-Json -Depth 5
```

```powershell
Get-PnpDevice -Class Bluetooth |
  Format-Table Status, FriendlyName, InstanceId -AutoSize
```

Record the output of `/api/health` while connecting, while streaming, and after
the failure. The fields of interest are `eeg_status`, `eeg_error`,
`eeg_device_name`, and application version.

## Controlled Test A: Official BrainAccess Software

Panel VR must remain closed throughout this test.

1. Power-cycle the sensor.
2. Open BrainAccess Board/Configurator.
3. Connect to `BA MINI 037`.
4. Start the official EEG viewer.
5. Observe live EEG for at least five minutes.
6. Record whether data freezes, whether an error is shown, and whether the blue
   LED changes.
7. Disconnect using the BrainAccess application before closing it.

Interpretation:

- If the official viewer also stops, investigate the device, battery, firmware,
  Bluetooth adapter, Windows driver, and power management before changing Panel
  VR.
- If the official viewer remains stable, continue to Test B. The Panel VR SDK
  lifecycle becomes the primary suspect.

## Controlled Test B: Panel VR 0.1.2

BrainAccess Board and all other BrainAccess applications must be closed.

1. Power-cycle the sensor again.
2. Start Panel VR once. Do not repeatedly reopen the executable.
3. Follow `panel-vr.log` and query `/api/health`.
4. Wait for both log messages:

   ```text
   BrainAccess EEG acquisition started
   BrainAccess EEG stream started
   ```

5. Do not create a session until `eeg_status` is `streaming` and plots move.
6. Observe the stream for at least five minutes.
7. If it fails, record:
   - exact failure time;
   - last time plots changed;
   - LED state before and after failure;
   - `/api/health` response;
   - whether Windows still lists the sensor as connected;
   - the complete log from application startup through failure.
8. If it remains stable, create a 60-second session, end it, download raw data,
   and verify that `eeg.ndjson` is non-empty.

## Controlled Test C: Recovery

Only run this after Test B can stream reliably.

1. While Panel VR is streaming, power the sensor off.
2. Confirm that Panel VR changes EEG state away from `streaming`.
3. Wait for at least one automatic retry.
4. Power the sensor on again.
5. Confirm that discovery, connection, and streaming recover without restarting
   Panel VR.

Expected log sequence:

```text
BrainAccess EEG connection attempt failed
Retrying BrainAccess EEG connection in 5 seconds
Connecting to BrainAccess EEG device BA MINI 037
BrainAccess EEG acquisition started
BrainAccess EEG stream started
```

If the log remains at `No devices found`, close Panel VR before power-cycling
the sensor. This distinguishes a sensor that is not advertising from a retry
loop or SDK state that is holding the Bluetooth connection.

## Evidence To Preserve

Collect these files and observations from each test:

- complete `panel-vr.log`;
- screenshots or copied JSON from `/api/health`;
- exported session directory, including `eeg.ndjson` and `session.json`;
- BrainAccess Board/Configurator error text;
- sensor firmware version;
- BrainAccess SDK/Core version;
- Bluetooth adapter name and driver version;
- whether integrated Bluetooth or the supplied USB adapter was used;
- sensor battery level;
- approximate distance between sensor and laptop;
- LED state at connection, first data, failure, and cleanup.

Do not combine logs from several uncontrolled restarts without noting each
restart time.

## Proposed Application Repair

If Test A is stable and Test B fails, implement the following narrow change:

1. Use BrainAccess Core and `EEGManager` directly instead of
   `acquisition.EEG`.
2. Initialize BrainAccess Core once when the real EEG service starts and close
   it once at application shutdown.
3. For each connection attempt:
   - scan and log all discovered device names;
   - create one manager and connect to the exact configured name;
   - configure the four EEG channels and sample rate;
   - register chunk and disconnect callbacks before starting;
   - load configuration;
   - start streaming.
4. Keep the chunk callback short: copy channel arrays into a locked buffer and
   return.
5. Track application-owned `connected` and `stream_started` flags. Do not call
   `stop_stream()` if startup never completed or the disconnect callback has
   already reported a lost connection.
6. Use the SDK disconnect callback as the primary connection-loss signal.
   Retain an 8-10 second missing-data timeout as a fallback.
7. Recreate only the manager during retry. Do not repeatedly initialize and
   close the global BrainAccess Core.
8. Enable BrainAccess native logs in the Panel VR log directory.
9. Log scan results, Core/firmware version, battery, callback count, last
   callback age, disconnect events, and cleanup stages.
10. Add backend health details to the dashboard so `connecting`, `streaming`,
    `error`, and the actual SDK error are visible separately from sample
    freshness.

Keep raw EEG transport unchanged: callback channel arrays should be sent to the
dashboard and recorded in `eeg.ndjson` without signal processing.

## Acceptance Criteria

The repair is ready for a Windows release only when:

- the official BrainAccess viewer streams for at least five minutes;
- Panel VR streams for at least five minutes without stale callbacks;
- a 60-second session produces non-empty, changing EEG channel arrays;
- frontend EEG status agrees with `/api/health`;
- powering the sensor off produces a clear disconnect state;
- powering it back on recovers streaming without restarting Panel VR;
- shutdown completes without callback, stop, disconnect, or manager cleanup
  exceptions.
