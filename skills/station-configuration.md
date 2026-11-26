---
name: station-configuration
description: Where each RocketWelder station setting lives (settings pages, station and program defaults, devices, pipelines, configuration files), what the important ones do and their defaults, which the person changes in the UI and which need RocketWelder, and when Claude may change one.
triggers: [settings, configuration, station defaults, initial settings, program defaults, devices page, pipelines, calibration photos, language, plugins, appsettings, change a setting]
---
# Station configuration

## When Claude changes a setting

| Station kind (`list_stations`, field `kind`) | Claude changes a setting |
|---|---|
| Simulator | When the person asks for that change |
| Real | When the person asks, Claude says the exact change (key, old value, new value) and makes it only after the person confirms it |

Claude never changes a setting the person did not ask for and never passes `confirmRealRobot`. Before any change, read the current value and tell it to the person.

## Where each setting lives

| Setting | Page: EN / PL menu name (route) | Claude reads | Claude changes | Saved in |
|---|---|---|---|---|
| Station programming defaults | Settings → Initial settings / Ustawienia → Ustawienia początkowe (`/programming-defaults`) | `get_station_defaults` | `set_station_default`, `clear_station_default` | the station's runtime configuration |
| A program's defaults | the program editor, gear button Initial settings / Ustawienia początkowe | `get_program_defaults` | `set_program_default`, `reset_program_defaults` | the program |
| Calibration photo timing | Calibration photos / Zdjęcia kalibracyjne (`/settings/calibration-photos`) | `get_calibration_photo_timing` | `set_calibration_photo_timing` | the station's runtime configuration |
| Devices (robot, welder, camera, distance sensor, Modbus, axis) | Devices / Urządzenia (`/devices`) | `list_devices` (name, type, connected) | — | the station's event store |
| Video pipelines | Pipelines / Potoki (`/pipelines`, top level of the menu) | `list_pipelines`, `get_pipeline_status` | `start_pipeline`, `stop_pipeline` | the station's event store |
| Commissioning, markers, calibrations | Commissioning / Uruchomienie (`/commissioning`) | the calibration and commissioning tools | — | the station's event store |
| Live signal scope and PID tuning | Signal Processing / Przetw. sygnału (`/signal-processing`) | — | — | — |
| Language | Language / Język (`/settings/language`) | — | — | the station's runtime configuration |
| Plugins | Plugins / Wtyczki (`/plugins`) | — | — | the station's runtime configuration |
| Portal registration | Integrations / Integracje (`/integration`) | — | — | the station's runtime configuration |
| Claude settings | Claude Code (`/settings/claude-code`) | — | — | not stated here |
| Licence | Licence / Licencja (`/settings/license`) | — | — | the station's runtime configuration |
| Server options (paths, ports, connections) | System (`/settings/system`), read only | — | — | configuration files |

All pages except Pipelines are in the Settings / Ustawienia group of the left menu. A station can hide menu entries, and Licence
shows only in some licence states; the route opens the page in either case, in both languages.

The station's pages have no login: whoever opens the station address can change what a page changes.

## Programming defaults

Station programming defaults are the values a program copies when it is created or reset. Changing one changes no existing program
and recompiles nothing. A program's own defaults are what its blocks inherit unless a block sets its own value; changing one
recompiles that program. `reset_program_defaults` copies the station's current values into the program.

`get_station_defaults` answers each key with its value and its layer: `station` (set on this station) or `builtIn`.

| Key | Built-in | Meaning |
|---|---|---|
| `Adaptation.OffsetTolerance` | `10:10` | How far the part moved. Tolerance band in mm, `accept:review`: up to accept the run goes on, up to review the operator is asked, beyond it the block stops |
| `Adaptation.PathTolerance` | `inf:inf` | How much the correction deforms the path. Tolerance band in mm; `inf` = unbounded |
| `Adaptation.AnchorBlur` | `true` | Blur the picture when finding circles and lines (adaptation anchors) |
| `Move.Travel`, `MovePtp.Travel`, `MoveJoints.Travel`, `Spline.Travel`, `Circular.Travel` | `20%` | Speed of that block type |
| `Corner.Travel`, `Corner.Turn` | `20%` | Speed and turn speed of a corner |
| `Corner.RadiusMm` | `5` | Corner radius, mm, above 0 |

A speed is a percent (`20%`), mm/s or cm/min. `set_station_default` and `set_program_default` take exactly one of band, speed, number
or flag; `set_program_default` needs the etag from `get_program_defaults`.

## Calibration photo timing

The wait after the arm stops before a calibration photo is taken, and the camera frames skipped after it. Built-in: 200 ms and 3
frames. The wait in force is never below the robot's own settle delay. Raise the wait when calibration photos are blurred or taken
late. It applies only to guided calibration photos.

## Devices and pipelines

A device is added, configured and removed on the Devices page by the person. `list_devices` shows each device's name, interface
(robot, welder, camera, …) and whether it is connected.

A pipeline is the camera's video processing. `start_pipeline` and `stop_pipeline` return when the command is accepted; read the
result with `get_pipeline_status`. A pipeline does not start while another pipeline uses the same Basler camera; stop that one first.

## Settings that need RocketWelder

The person cannot change these: they live in files on the station, and the station has no shell for the customer.

| Setting | Where |
|---|---|
| Server paths (recordings, repositories, models), EventStore connection, ports | `docker-compose.yml` of the station release and the station's `appsettings.runtime.json` |
| Adaptation dataset recording (`AdaptationDataset:Enabled`), recording destination | the station's `appsettings.runtime.json` |
| Anything in `.env` or `docker-compose.override.yml` | the station's compose folder |

Ask RocketWelder for these. Say the setting, the value wanted and why.

## Missing read tools

| Tool | Effect | Endpoint | Owner |
|---|---|---|---|
| `list_device_configurations` | read | rw2 `GET /api/peripheral-devices` (every device with its properties and health, no parameters), marked `.ForAgents("list_device_configurations", ToolEffect.Read)` | rw2 |
