---
name: troubleshoot-devices
description: Help a person when a device of a RocketWelder station misbehaves — the Fairino robot, the Megmeet welder, a camera or video pipeline, the program overlay, a linear track (generic axis) or a Modbus device. Per device - symptom, what to read (MCP tool, station page, URL), known cause, what to do or what to send us.
triggers: [troubleshoot, device error, robot error, error 14, error 154, MoveJ rejected, MovePtp, Err7, welder fault, overlay gone, overlay slow, pipeline failed, camera, axis may still be moving, track, carriage, modbus, red bar]
---
# Troubleshooting connected devices

You read; the person acts. You have the **rocketwelder** MCP tools and the station's pages, which the person opens in a browser
at the station url (`list_stations` shows it as `url`). There is no shell on the station and no device log you can read.

## Rules

- Never move the robot, an axis or the welder, and never start a program on a `Real` station (`list_stations` → `kind`).
- Never change a device setting, a tool frame, a pipeline or a plugin unless the person asks for that exact change. Starting or
  stopping a pipeline is a change: ask first.
- "Reset", "Home", "Enable", "Reset fault" and "Reset all errors" are pressed by the person at the station, never by you.
- On a `Real` station, if you are unsure what a step does to the cell, stop and ask.
- Quote the error text exactly as the station gave it. Do not repeat a refused call unchanged.
- A tool named here that is not in your tool list is not on this station's rw2 version: use the page named beside it.

## First reads (every device)

1. `list_stations` → the selected station, its `kind` and `url`.
2. The rw2 version: the person opens `<url>/version` (`{version, gitSha}`). Several faults below are fixed only from a version on.
3. `list_devices` → each device's name, interface and `Connected`.
4. The person opens `<url>/devices`: the Status column shows each device's state (for a PLC: `Online`, `Unreachable`,
   `Connecting...`, `Connection failed`).
5. A program that stopped with an error: `get_program_status` (`Last Error` is the device's message) and `get_run_progress`
   (which block is `Failed`).

## Fairino robot

rw2 drives the arm over the controller's SDK. A point-to-point move (`MovePtp`) asks the controller for the joints of the target
(inverse kinematics), then sends `MoveJ` with those joints, the target pose, the configured tool number and workpiece (user)
frame 1. A refused move carries the controller's number only: `(error N)`; a refused jog reads `Robot error N.`

| Symptom | Read | Known cause | What to do |
|---|---|---|---|
| `MovePtp: MoveJ rejected for {…} (error 14)` | `get_program_status` → `Last Error`; `get_robot_pose`, `get_robot_joints` | 14 = `ERR_EXECUTION_FAILED`. The joints were solved, so the controller itself refused the command: a standing fault, the controller's mode, or the arm not enabled | The person checks the pendant for a standing alarm, the controller's mode and that the arm is enabled, and clears it there before the next run. Still 14: send us the `Last Error`, the time, the pendant's alarm text |
| `MovePtp: inverse kinematics failed for {…} (error N)` | the same | The controller found no joints for that pose | Send us the pose from the message and the point's name |
| `MoveJ rejected … (error 154)` | the person opens `<url>/api/robots/default/tool-frame`: `ToolId` (the tool rw2 commands), `ActiveTool` (the tool the controller uses) | 154 = motion planning failed: the joints and the pose sent with them do not match. Found this week: the tool frame or the workpiece (user) frame on the controller is not the one rw2 commands | `ToolId` ≠ `ActiveTool`: the person opens Devices → Calibrate TCP and presses Select. Same tool: ask which workpiece frame is active on the pendant and what it holds (rw2 moves in frame 1); send us both frames and the `Last Error` |
| `Refusing to move: <robot>: tool T with record R is selected but the controller is using tool N …` | `<url>/api/robots/default/tool-frame` | The tool selected in rw2 is not the controller's active tool | The person opens Calibrate TCP on the Devices page and presses Select |
| `… controller code 99 …` / jog refused, safety | the pendant | A safety stop (SI0/SI1) is active: guard, emergency stop, a person in the cell | The person clears the safety circuit. Nothing is wrong with the drive |
| `controller fault 1/89 — Peripheral (UDP) communication abnormal — link to the PLC is down` / an external-axis call `refused with controller code 14` | Devices page, the robot's jog panel | The controller's UDP link to the track PLC is down. rw2 runs `ExtDevUDPClientComReset` by itself | Still standing: the person checks the PLC and its cable; the controller's web console alarm offers "Restaurer la connexion" (restore the link) |
| Program screen and overlay freeze while the arm moves, video fine | `<url>/version` | bug-074: a tool-frame read (`GetTCPOffset`) was answered only after the move ended | Fixed from rw2 **2.93.0**. Older: tell the person it is known, fixed by the update |
| The arm keeps moving after STOP | — | The controller refused the stop | The person uses the physical emergency stop now. Then send us the time |
| `get_robot_pose` says "Robot is disconnected" | `list_devices` | rw2 has no session with the controller | The person checks the controller is on and reachable; Devices page → the robot's Connect |

The controller's fault code (main/sub) is shown only in the robot's jog panel and the Devices page "Reset all errors" dialog.

## Megmeet welder

rw2 talks to the welder over EtherNet/IP through the Megmeet plugin. The welder's fault code and its latch are shown on the
welder's panel, row "Power source". The plugin clears Err27 and Err28 by itself; every other code waits for the person.

| Symptom | Read | Known cause | What to do |
|---|---|---|---|
| Panel shows `fault, code 7` (Err7) | the welder's panel `<url>/welders/{id}` (phone: `<url>/mobile/welder/{device}/panel`); `<url>/plugins` → the Megmeet plugin's installed version | Seen at a station: a run whose arc never struck, then STOP, left the arc command (E01) on for 74 minutes and the welder latched Err7. Fixed in Megmeet plugin **1.2.1** | The person clears it on the welder or presses "Reset fault" on the panel (shown while the fault is latched). Plugin older than 1.2.1: they update it on `/plugins`. Err7 after 1.2.1: send us the time, the run and the plugin version |
| `Err27 — external communication disconnected`, `Err28 — external communication abnormal` | the panel | The link to the robot side dropped | Cleared by the plugin after it reconnects. Repeating: check the network cable |
| `Err30 — given setting out of range` | the panel; the program's weld values (`get_block_values`) | A value sent to the welder is outside what it accepts | Read the block's weld values; change them only if the person asks |
| `Err31 — robot host not ready (E02)` | the panel | The welder waits for the robot-ready signal | Send us the time and the panel |
| `fault, code N` (any other) | the panel | No explanation in the plugin | The welder manual, chapter "error codes"; send us the code |
| Welder not connected | `list_devices`; Devices page | No connection to the welder | The person checks the cable and IP; send us the Devices page status text |
| `STOP FAILED — THE ARC MAY STILL BE LIVE` | — | STOP did not reach the welder | The person uses the physical emergency stop now. Then send us the time |

"Reset all errors" on the Devices page does not reset the welder.

## Camera and video pipelines

A camera's video runs in a GStreamer pipeline. States: `Stopped`, `Starting`, `Running`, `Stopping`, `Failed`.

| Symptom | Read | Known cause | What to do |
|---|---|---|---|
| No video | `list_pipelines`, `get_pipeline_status`; `get_camera_frame` | The pipeline is not `Running` | With the person's yes: `start_pipeline`. `Failed`: the person opens `<url>/pipelines` and hovers the state for the error |
| `Cannot start: pipeline '…' is already using this Basler camera … Stop it first.` | `list_pipelines` | Two pipelines on one camera | Stop the other one (with the person's yes), then start |
| Pipeline stays `Starting` for 2 minutes, then `Failed` ("was not ready") | the pipeline in the designer (`<url>/pipeline/{id}`) | bug-084: `zerofilter` with `passthrough` marked configured hangs at launch | The person unticks `passthrough`'s "configured" in the pipeline editor |
| A pipeline with a processing container fails after 30 s ("hasn't created the buffer in 00:00:30") | — | bug-083: the container gets a fixed 30 s to start | Known, not fixed. Send us the pipeline name and time |
| `get_camera_frame` → "Camera frame is unavailable." | `list_pipelines` | The camera's pipeline is not running | As "No video" |
| Red bar, page stops working, on STOP or when leaving the program editor | `<url>/version` | bug-075 / bug-081 | Fixed from rw2 **2.93.0**. Reload the page |

## Program overlay (points on the video)

The program's points are drawn over the video by the page or by the RocketWelder Player (native player). rw2 sends the overlay
about 10 times a second.

| Symptom | Read | Known cause | What to do |
|---|---|---|---|
| Overlay gone in the Player, comes back by itself (often while jogging) | Player log `%LOCALAPPDATA%\RocketWelderPlayer\logs\client.log`: lines `overlay_cost_refused … cost=… limit=…` | bug-077: the Player hid a frame whose estimated draw cost passed a limit. Fixed on native-player master, **not in a release** (v1.3.1 has the limit) | Tell the person it is known; the fix comes with the next Player release |
| Overlay slow (one update per move) while the arm moves | `<url>/version` | bug-074 (Fairino section) | Fixed from rw2 **2.93.0** |
| Points in the wrong place on the live picture | `get_live_overlay` / `get_live_projection` with the `id` of the program (rw2 2.93.0 on) | Calibration or adaptation in force | `list_skills`: load the calibration or adaptation skill if the station has one |

Player started with `--debug` (default `--debug-http-port 9223`): on that computer `http://127.0.0.1:9223/v1/players` shows per
player `fps`, `frameAgeMs` and `overlayMessages` (messages received). `overlayMessages` climbing with no overlay drawn = the
Player drops it; not climbing = rw2 is not sending.

## Linear track (generic axis)

A track is a PLC-driven axis that rw2 commands over Modbus TCP (plugin `ModelingEvolution.GenericAxis.Plugin`). Its messages
read `<axis>: <error>: <what>. Read <register> (<address>) = <value>`.

| Symptom | Read | Known cause | What to do |
|---|---|---|---|
| `STOP INCOMPLETE — AN AXIS MAY STILL BE MOVING` after many STOP presses in a row | `<url>/version`; `<url>/plugins` → the generic-axis plugin's installed version | bug-076: concurrent Stops raced on the PLC's command registers; the carriage had stopped | The person checks the carriage is still. rw2 2.93.0 plus axis plugin 0.2.1 fix it; plugin 0.2.1 is not released yet. A single press is fine |
| `… refused in ErrorStop (…); call ResetAsync` | the axis page `<url>/mobile/axes/{device}` | The PLC is in ErrorStop | The person reads the fault (table below), removes its cause, presses Reset |
| `… refused while Disabled; power on or home first` | the axis page | The drive is off | The person presses Enable or Home |
| `… CommunicationLost: … failed twice (reconnected once)` / `did not attach` | `list_devices`; Devices page | Network, IP, port or unit id of the PLC | The person checks the PLC's power and cable; send us the message |

| Fault code | Meaning |
|---|---|
| 1 | drive fault |
| 2 | limit switch tripped (LimitMin/LimitMax) |
| 3 | following error |
| 4 | the PLC watchdog tripped; Reset, then re-command (no re-home) |
| 5 | homing failed in the PLC sequence |
| 6 | the PLC lost its drive link |
| 7 | safety circuit (E-stop / guard) |
| 0 | the PLC reports ErrorStop without a fault code |
| other | vendor fault N: the PLC's own manual |

Reset clears the fault and leaves ErrorStop; it is refused while the link to the PLC is down.

A track attached to the Fairino controller (not a PLC on Modbus) answers with the robot's codes: see "controller fault 1/89" above.

## Modbus devices

A tagged Modbus device maps names (tags) to registers; tags are on the device's Edit dialog in `<url>/devices`.

| Symptom | Read | Known cause | What to do |
|---|---|---|---|
| `read_modbus_tag` answers an error (404 Not Found) | `read_modbus_tag` with `deviceName` and `tagName` exactly as on the Devices page; Devices page Status | The station answers the same for an unknown device, an unknown tag and a failed read | Check the names first. Names right: the Status column says why (`Unreachable` = no answer to ping, `Connection failed` = no Modbus connection) |
| `Unreachable` | Devices page | The device is off or the IP is wrong | The person checks power, cable, IP |
| `Connection failed` | Devices page | The device answers ping but not Modbus TCP: port, or the device's Modbus server off | The person checks the device's Modbus settings against the device's Edit dialog |
| A tag shows red on the dashboard's PLC card | the dashboard | That tag's read failed (a wrong unit id or register fails every read) | Check the device's `UnitId` and the tag's register on the Edit dialog |

## What to send us

When a fault is not in this skill or does not clear: the station's `version` and `gitSha`, the time (with time zone), the exact
error text, `get_program_status` / `get_run_progress` of the run, the device's line from `list_devices`, and what the pendant or
the welder's front panel shows. The station's own log is not reachable from here; we read it from the station.
