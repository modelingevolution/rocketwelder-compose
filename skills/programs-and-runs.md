---
name: programs-and-runs
description: How a RocketWelder program is built (repositories, programs, blocks, points, values and their defaults), how to read it, how it is compiled, run and watched, and what a run's states and refusals mean. On a Real station you read and explain; the person runs and stops.
triggers: [program, block, program tree, points, block values, program defaults, compile, run program, dry run, run failed, run cancelled, run progress, program history, check program]
---
# Programs and runs

Related skills (`load_skill`): `offline-programming` (a program from a part's seams, on a twin), `adaptation-setup` (an
Adaptation block's views and marks), `troubleshoot-devices` (a run stopped by a robot or welder fault).

## Rules

- **You never move a real cell.** On a station whose kind is `Real` (`list_stations`) you never call `run_program`, and you
  never cancel and run again. The person runs and stops the program on the station. You read and explain.
- Never pass `confirmRealRobot`, on any tool.
- `cancel_program` only when the person asks you to stop a run. The station's **STOP** is always the person's first way.
- Edits (blocks, points, values, defaults, compile) only when the person asks. Say what will change first.
- Lengths are mm, angles degrees, robot base frame unless a tool says otherwise.

## How a program is built

| Part | What it is | Read |
|---|---|---|
| Repository | a local git repository of programs on the station. Every edit is one commit | `list_repositories` |
| Program | a block-editable program in a repository, compiled to a C# plugin | `list_programs` (optional repository filter) |
| Block tree | the ordered blocks: blockId, type, properties, disabled, and the tree's etag | `get_program_tree` (`programId`) |
| Points | the taught points: pose (x, y, z mm; rx, ry, rz deg), joints (deg) or none, external axes, origin (Taught, View, Unknown), captured at | `get_program_points` (`programId`, optional `name`) |
| Values | a block's values as stored and as the run uses them, with the layer each comes from | `get_block_values` (`programId`, `blockId`) |
| Program defaults | the values every block inherits unless it sets its own, with the station's value beside each | `get_program_defaults` (`programId`) |
| Station defaults | the values copied into a program when it is created or reset | `get_station_defaults` |
| History | the commits, newest first: time, sha, one-line description | `get_program_history` (`programId` or `repositoryId`) |

A value comes from the first layer that sets it: **block → program default → built-in**. Station defaults reach a program only
when it is created or its defaults are reset.

## The blocks

| Block | What it does |
|---|---|
| Point | declares a point (its pose is written with the point, not with the block) |
| MovePtp | joint-interpolated move to a point: an approach, a retract, a viewing pose |
| Move | linear move: the weld move between ArcOn and ArcOff; the torch angles are the target point's rx, ry, rz |
| MoveJoints | drives to the point's taught joints (no inverse kinematics); travel is a % of the robot's joint speed |
| Circular · Circle · Corner · Spline | an arc through a via point · a ring around a centre · a rounded move through a point · a smooth move through waypoints |
| SetWelderParams | the arc job; before ArcOn |
| ArcOn · ArcOff | strike · stop the arc |
| WaitArcStable · WaitMotionRelease · ArcParallel | older programs: wait for a stable arc · wait until the welder releases the robot · strike, hold, stop in the background. Newer programs carry these as options on ArcOn |
| Delay | wait a number of seconds |
| Pause | stops for the operator. A real run started through the MCP (no operator at the station) is refused while one is enabled |
| Adapt | adaptation: corrects the points from the camera (`adaptation-setup`) |
| SetEmptyReference | photographs the empty fixture for the adaptation blocks after it |
| TouchSense | finds the part by touching it |
| AxisMove | drives an external axis the cell declares |
| Frame | a group whose blocks run in a frame shifted and turned from the robot base |
| Stand | a group: a place of the robot on a linear track |
| Custom | a line of C# written as is |

A seam reads: MovePtp approach → SetWelderParams → ArcOn → Move to the end → ArcOff → MovePtp away.

A switched-off block (`disabled`) stays in the program and is not run.

## Editing (only when the person asks)

- Every block edit needs the **etag** from `get_program_tree` or the previous edit. A stale one is refused with 409: read the
  tree again and repeat.
- Blocks: `add_program_block`, `edit_program_block`, `remove_program_block`, `move_program_block`, `set_block_enabled`.
- Points: `put_program_point`, `put_program_points` (a Point block declares the name first). Moving a point's pose drops its
  old adaptive correction.
- Values: `set_block_value` / `clear_block_value` take effect on the next run, with no compile.
  `set_program_default` / `reset_program_defaults` need the etag from `get_program_defaults` and recompile the program.
- After a block or point edit: `compile_project` (`programId`).
- `capture_point` records where the robot stands now. It does not move the robot.

## Compile

`compile_project` with `programId` waits until the build settles. It answers the discovered programs, or the failure with its
diagnostics. If it answers "still running", follow it with `get_compile_status` and do not compile again. `get_compile_status`
gives the outcome `Unknown`, `InProgress`, `Succeeded` or `Failed`, with the diagnostics of a failed build.

## Check

`check_program` (`programId`, optional `viewId`) checks every adaptation block's views against the **simulator**. It reports
numbers only, with no pass or fail: projected vs true pixel, mark vs projection (px and mm), what each mark's ray hits and how
far from the taught point, the angle of the view to the anchor plane. It needs a station with a simulator address. On a real
station without one, it says so and calls nothing.

## Running

On the station the person presses **Run** in the program editor, and **STOP** stops it. A run's page is
`/station/run/<run id>` (phone: `/mobile/station/run/<run id>`) while it runs. An ended run, with its own error:
`/program-executions/<run id>`.

A run is **real** (`dryRun` false: the arm moves and the arc is on) or **dry** (`dryRun` true: the arm still moves through every
motion, only the welder does nothing).

A simulator station only: `run_program` (`programId`, `dryRun`, optional `fromStart`), then follow it.

| Tool | Answers |
|---|---|
| `get_program_status` (`programId`) | the state `Idle`, `Running`, `Finished`, `Failed` or `Cancelled`, and the last run's summary. It carries the run id only while the run is in progress |
| `get_run_progress` (`programId`, `runId`) | the run's state, dry or not, start, end, duration, arc-on seconds, and one row per enabled block |
| `wait_for_run` (`programId`, `runId`, `timeoutSeconds` up to 600) | waits for the end. "Still running": call it again |
| `watch_run` | holds adaptation reviews open for an answer (`adaptation-setup`) |

A finished run's id comes from `run_program`'s answer or from the run page's address.

**Block states** in a run: `Pending`, `Running`, `Done`, `Failed`, `Interrupted` (stopped while working), `NotRun` (the run
ended before reaching it).

**A run refused before anything moves** (409, with the reason):

- a real run through the MCP of a program with an enabled Pause block (disable the Pause, or run dry)
- adaptive points not adapted
- a run already in progress

`get_run_progress` answers 404 "did not start: <reason>" for a refused run.

A run that ends `Failed` or `Cancelled`: the failed block's row names where it stopped, and the answer carries the
station's last error (for example "MoveLin rejected (409): Collision …"). The last error is kept for the program's latest
run only; `get_program_status` shows it as Last Error. For an older run, `get_run_progress` still prints that latest
error, which belongs to another run: ignore it, and read the failed block's row and the run's page in the program
executions (`/program-executions/<run id>`), which shows that run's own error. The error shown is right only for the
program's latest run. A robot or welder fault: `troubleshoot-devices`. An adaptation that was blocked or rejected:
`adaptation-data-and-analysis`.

## Undoing a change

Every program edit can be undone. Each block, point, block value and program default edit is one program history step,
and `get_program_history` lists them.

- **Undo in the program editor** (the ↶ button, its tooltip "Undo: <step>") reverses the program's most recent step and
  records the undo as a step of its own. Press it again to go back one more step. Redo (the button beside it, or Ctrl+Y) re-applies; Undo is also Ctrl+Z.
- The MCP has no undo tool yet. Until it has, tell the person to press Undo, or write the old value back:
  - `set_block_value`: set the old value again, or `clear_block_value` when the block had none (`get_block_values`
    shows both before the change).
  - `set_program_default`: set the old value again (`get_program_defaults` before the change).
  - `put_program_point` / `put_program_points`: write the old pose, joints and axes (`get_program_points` before the
    change).
  - A block edit: the opposite edit (`remove_program_block` after an add, `set_block_enabled` back, `move_program_block`
    back), or Undo in the editor.
- Before any change, read and keep what it replaces. After undoing a block or point edit, compile as after the edit.

## What changed in a program

`get_program_history` lists every edit as one commit. An agent's edit reads "… via API". A deleted program's history is
read with the `repositoryId`.
