---
name: rocketwelder-overview
description: Load first when a question about a RocketWelder station is vague or you do not know which skill fits. What a station is, its main pages, Real versus Simulator stations and the rules, and which skill to load for each kind of question.
triggers: [help, what is, how does, how do I, station, RocketWelder, rw2, Neuron, problem, not working, where do I find, explain]
---
# RocketWelder station: overview and index

This skill is the index. Load the skill the routing table names, then work from that skill.

## What a station is

| Part | What it is |
|---|---|
| Neuron | the station's computer. It runs rw2 and its event store in Docker |
| rw2 (RocketWelder) | the station's application: web UI, REST API, programs and runs, calibration, adaptation, device drivers. You reach it through the **rocketwelder** MCP tools |
| Robot | the arm, for example a Fairino cobot |
| Welder | the welding power source, for example Megmeet, through its plugin |
| Camera and pipelines | each camera's video runs in a GStreamer pipeline; programs, calibration and adaptation use its frames |
| Axis | a linear track or positioner, driven by a PLC (generic axis) or by the robot controller |
| Modbus devices | PLCs and peripherals that rw2 reads by named tags |
| Twin (simulator) | a simulated copy of a cell. A `Simulator` station's robot is simulated; `list_stations` gives a station's twin as `simulatorUrl` |
| RocketWelder Player | the native app that shows rw2 with native video, on a station screen, a Windows PC or a tablet |
| AutoUpdater | the service on the Neuron that installs station releases. Its Apps page offers the Player downloads |

## Real and Simulator stations

`list_stations` lists the stations; `select_station` picks the one every other tool acts on. Each station's `kind` is `Real` (a
real cell) or `Simulator` (a twin).

- You never move a `Real` robot and never pass `confirmRealRobot`. `run_program` and `decide_adaptation` refuse to go ahead on a
  `Real` station without it.
- On a `Real` station, you read and explain. The person moves, runs, resets and changes things at the station.
- There is no shell on the station. You use the MCP tools, the station's pages (the person opens `<url>/…`; `url` comes from
  `list_stations`) and the REST routes that a skill names.
- Change a setting only when the person asks for that exact change.

## Main pages

| Page | For |
|---|---|
| `/` Dashboard | the Neuron's performance monitor (load, resources) |
| `/automation` Automations | the station at a glance: camera, robot, welder and PLC cards, programs, quick actions |
| `/programs` Programs | the program list; opens the program editor `/teach/program/{id}` |
| `/repositories` Repositories | the program repositories (git) |
| `/station` | the operator's station view, where runs are started and followed |
| `/pipelines` Pipelines | the camera pipelines and their state |
| `/recordings` Recordings | recorded camera video |
| `/devices` Devices (Settings) | every device, its status, its settings, "Reset all errors" |
| `/commissioning` Commissioning (Settings) | marker, TCP check, health check; calibrations at `/commissioning/calibrations` |
| `/programming-defaults` Initial settings (Settings) | the station's program defaults |
| `/plugins` Plugins (Settings) | installed device plugins and their versions |
| `/settings/system` System (Settings) | the server's system configuration, read-only |
| `/openapi` | the REST API reference |

## Which skill to load

`list_skills` shows what this station has. If the skill named here is not listed, say so and answer from this overview.

| The person asks about | Load |
|---|---|
| a device error or fault: robot, welder, camera, pipeline, track, Modbus, the overlay, STOP alarms | `troubleshoot-devices` |
| setting up adaptation for a part: views, photos, marking points, intermediate positions, corrections | `adaptation-setup` |
| an adaptation result: is the correction good, the view photos, overlays, projections, what to send us | `adaptation-data-and-analysis` |
| programs: blocks, points, values, compile, check, run, run states, why a run failed | `programs-and-runs` |
| calibrating the camera: lens, joint corrections, hand-eye, health check | `calibration` |
| the RocketWelder Player: install, connect, its debug mode, its logs, its known faults | `native-player` |
| which version runs, updates, the AutoUpdater, a failed update | `updates-and-versions` |
| where a setting lives, station or program defaults, the settings pages, changing a setting | `station-configuration` |
| writing a program for a part on a simulator twin, from the part's seams | `offline-programming` |

A question that spans two rows: load both.

## First reads for any station question

1. `list_stations` → the selected station, its `kind` and `url`.
2. `list_devices` → the devices and whether each is connected.
3. The rw2 version: `get_station_version` when your tool list has it, else the person opens `<url>/version`.
