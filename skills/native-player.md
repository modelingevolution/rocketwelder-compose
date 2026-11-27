---
name: native-player
description: What the RocketWelder Player (native player) is on a station screen, a Windows PC or an Android tablet; how it connects to the Neuron; its debug mode and debug REST (npdebug); where it logs; its known faults with the version that fixes each; what to send us.
triggers: [native player, RocketWelder Player, kiosk, station screen, player debug, npdebug, player log, client.log, overlay gone, double point, tap twice, see-through, player version]
---
# RocketWelder Player (native player)

The Player shows the Neuron's web UI (rw2) in an embedded web view and plays the camera video natively under it, with the
program overlay drawn natively on the video. rw2 sees it by its user agent (`RocketWelder-Kiosk…`) and leaves the video to it.

| Host | Where | Installed from |
|---|---|---|
| Linux kiosk (arm64, Debian 13) | a dedicated screen device or the station's own screen; it owns the machine (kiosk user, auto-login) | `.deb` |
| Windows 10 22H2 / 11 x64 (WebView2) | an office or cell PC, per user, no administrator rights | `.msi` |
| Android 12+ (arm64), preview | a tablet | `.apk` |

All three are offered on the station AutoUpdater's Apps page.

## Rules

- Never move a `Real` robot; never pass `confirmRealRobot`.
- Installing, updating, restarting a Player and its Neuron address are the person's: no tool of yours does them.
- Never call `POST /v1/input`: a synthetic tap can press a button that moves the robot.
- `POST /v1/players/{id}/url` only when the person asks for it. Before it, read the player's `url` from `/v1/players`; to undo,
  post that url back.
- Device faults seen through the Player (robot, welder, pipelines, rw2 overlay rate, red bar): load the `troubleshoot-devices`
  skill.

## How it connects

- **Address:** the Neuron's base url `http://<IP>:<port>`, the port included. Windows and Android refuse https and a path.
  Windows: the start screen or Settings → Neurons. Android: settings sheet, "Neuron base URL". Linux kiosk: `KIOSK_URL` in
  `/etc/native-player/kiosk.conf` (default `http://localhost/auto-preview`, the station's own screen); changing it needs a
  shell on that device (`sudo kiosk-config --url …`), so it is the installer's job, not yours.
- **Start-up:** the Player waits for the Neuron's `/health` before it opens the page. Windows shows `Waiting for the Neuron …`;
  Linux shows a spinner, then `Waiting for server...` after 30 s.
- **Video**, per host:

  | Host | Plays |
  |---|---|
  | Windows, Linux | RTP/JPEG over UDP with forward error correction; MJPEG over HTTP if no RTP packet arrives within 5 s |
  | Linux on the Neuron itself | also shared memory |
  | Android | MJPEG over HTTP only |

  For RTP the Player registers with the Neuron from one UDP socket, so no inbound firewall rule is needed.
- Linux: Ctrl+Shift+V shows on each video the protocol now playing (`shm`, `rtp`, `mjpeg`; `mjpeg` after a fallback), the
  resolution and the fps.

## Version

| Host | Where |
|---|---|
| Windows | Esc (or the edge swipe) opens Settings → About: `Version x.y.z (build)` (Polish: Ustawienia → O aplikacji, `Wersja x.y.z (build)`) |
| Linux kiosk | the installed `native-player` package version (the person who set up the device reads it) |
| Android | the Android app info |

Latest release: **v1.3.1**. Fixes merged after it are on native-player master only, until the next release.

## Debug mode and the debug REST (npdebug)

Debug runs only when the Player is started with `--debug`. It listens on 127.0.0.1 only, so it is read on the Player's own
computer. Windows: `RocketWelderPlayer.exe --debug [--neuron http://host:port] [--debug-port 9222] [--debug-http-port 9223]`;
Settings → Debugging (Debugowanie) then shows `On` and both ports. The Linux kiosk starts without `--debug`. Android: with
diagnostics on, npdebug is at 127.0.0.1:9223 on the tablet, reached from a computer with `adb forward tcp:9223 tcp:9223`.

| Port (default) | What |
|---|---|
| 9222 | the web view's inspector: Windows = Chrome DevTools Protocol (CDP); Linux = WebKit inspector (not CDP) |
| 9223 | npdebug, read-only routes below |

| Route | Answer |
|---|---|
| `GET /v1/players` | each player: `status`, `fps`, `frameNo`, `frameAgeMs`, `overlayMessages` (messages received per overlay stream); the window size; stream tokens redacted |
| `GET /v1/metrics` | the Player's counters |
| `GET /v1/log?since=<unix ms>` | the last log lines kept in memory (4 MiB), `<unix-ms> <level> <text>`, tokens redacted |
| `GET /v1/screenshot.png` | the window as the person sees it |
| `GET /v1/players/{id}/jpeg` | the player's last video frame |
| `GET /v1/players/{id}/composite.png` | the video with its overlay |
| `GET /v1/players/{id}/overlays` | the overlay streams; `…/overlays/{stream}.png` one drawn layer |

Reading `/v1/players` taken a few seconds apart:
- `frameNo` not growing or `frameAgeMs` large: the video is not arriving.
- `overlayMessages` growing but no overlay drawn: the Player drops it.
- `overlayMessages` not growing: rw2 is not sending it.

## Logs

| Host | Log |
|---|---|
| Windows (only host with a log file) | `%LOCALAPPDATA%\RocketWelderPlayer\logs\client.log` on the PC that shows the Player, never the Neuron; the run before is `client.log.1`. Claude Code on that PC reads it itself; with Claude Desktop the person opens it |
| Linux | no log file (stderr only); with `--debug`, `GET /v1/log` |
| Android | logcat, tag `NPKIOSK` |

## Known faults

| Symptom | Host | Cause | Fixed in |
|---|---|---|---|
| The overlay disappears, comes back by itself (often while jogging); the log (see Logs) has `overlay_cost_refused … cost=… limit=…` | all | bug-077: a frame whose estimated draw cost passed a limit was drawn empty | native-player master; **not in a release** (v1.3.1 and older have it) |
| Adaptation photo shows no points, all marking tools disabled | Windows, Linux | bug-078: the photo overlay was not mounted in the Player | rw2 **2.93.0** (`<url>/version`) |
| A circle mark appears only after a refresh | all | bug-079 | rw2 **2.93.0** |
| One tap on the adaptation photo writes two points, mostly in the first seconds after the view opens | Linux | bug-082: WebKitGTK clicked a tap the page had already handled | native-player master; **not in a release**. Until then the person deletes the extra point in the view |
| During a run, the adaptation window offers no frame grab for marking | all | rw2 leaves the grab out in the Player | open; the person marks that step in a browser |
| Parts of the page are see-through on Windows: the desktop and old frames show between cards | Windows | known, under work | open |
| `The web view keeps failing` / `Microsoft Edge WebView2 Runtime is not installed` | Windows | WebView2 Runtime missing or crashing | the person installs or repairs the WebView2 Runtime from Microsoft |
| `The debug port is in use` | Windows | another program holds 9222 or 9223 | start with other `--debug-port` / `--debug-http-port` values (they must differ) |

## What to send us

- The host and the Player's version, and the rw2 version (`<url>/version`).
- The time, with the time zone, and the page that was open.
- Windows: `client.log` and `client.log.1`.
- With `--debug`: `/v1/players` read twice a few seconds apart, and `/v1/screenshot.png`.
