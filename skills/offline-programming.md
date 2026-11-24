---
name: offline-programming
description: Write and run a welding program for a part on a simulator twin, from the seams on the part. rw2 generates the program; you do not compute points or add blocks.
triggers: [offline programming, program from seams, seams to program, weld program, create_program_from_seams]
---
# Off-line programming: seams → program → run → seam verdicts

Follow the steps in order. Do not skip a step and do not add your own.
rw2 plans every seam itself (torch angles, approach and retract points, track stops, splits of long seams). You never compute a
point, never add a block one by one, and never move the robot with the simulator's move tools.

Two MCP servers are used: **rocketwelder** (the station's rw2) and **simulator** (the station's twin).

## Rules

- Simulator stations only. If `list_stations` shows the selected station with kind `Real`, stop and tell the person. Never select a
  `Real` station.
- All lengths are mm, all angles degrees.
- A refusal is an answer: read its text. Do not repeat a refused call unchanged.
- If a step does not give the answer this skill says it gives, stop and report the step number, the call and the answer.

## Step 1. The station and the twin

1. rocketwelder `list_stations`. The answer names the selected station. If `selected` is null: `select_station` with the station the
   person named. Its kind must be `Simulator`.
2. simulator `list_simulators`. If `selected` is null: `select_simulator` with the twin the person named.

## Step 2. The placed parts and their seams

1. simulator `list_assets`. It lists everything placed in the scene with its `label` (for example `part/door-a`).
   Find the parts the person named and write down each `label` exactly as listed.
2. For each part: simulator `get_placed_part_seams` with `placement` = the label. The answer lists that part's seams.
   Write down how many seams each part has. (rw2 chooses the welding order of new seams itself: seams of one member together,
   members along the rail. Seams a program already has keep their place.)
   If a part has no seams, stop and report it: putting seams on a part is not part of this skill.

## Step 3. The program

1. rocketwelder `list_repositories`. Use the repository the person named; with only one, use it.
2. rocketwelder `create_program` with that `repositoryId` and a new `name` (letters and digits, starting with a letter).
   Write down the `programId`.

## Step 4. The welding speed

The travel speed is a program default. Set it BEFORE step 5: a speed set after the program is created does not reach the blocks
that already exist.

1. rocketwelder `get_program_defaults` with the `programId`. Write down the `etag`.
2. rocketwelder `set_program_default` with `programId`, `key` = `Move.Travel`, the `etag`, and
   `speed` = `{ "value": <the speed the person gave>, "unit": "MmPerSecond" }`.
   If the person gave no speed, use 8 mm/s and say so in your report.
   If it answers `ProgramEtagMismatchException` (HTTP 409), the program changed since the etag was read: repeat 1 and 2 with the
   fresh `etag`.

`Move.Travel` is the speed of the weld moves. The approach and retract lines and the moves between seams run at the
non-welding speed (`MovePtp.Travel`); leave it as it is unless the person says otherwise.

## Step 5. Create the program from the seams

rocketwelder `create_program_from_seams` with:

- `id` = the `programId`
- `placements` = the labels from step 2, as a list (for example `["part/door-a", "part/door-b"]`)
- `verdictToleranceMm` = the tolerance the person gave; none given: 2
- `restartOverlapMm` = the overlap the person gave; none given: 25
- `clearanceMm` = the clearance the person gave; none given: 25. Everything except the torch in its own joint must stay this far
  from the part, the fixtures and the cell.

Planning takes from a fraction of a second to about five seconds per seam, so a part with 30 seams can take two to three minutes.
Wait for the answer; do not call again while it runs. The answer lists every seam with an `answer`:

- `Planned`: nothing to do.
- `NeedsValue`: `missing` names the value. Call `create_program_from_seams` again with that value.
- `Unreachable`: go to step 6 for that seam.

Also read:

- `returnFailure`. Null: the program ends where it started, so it can be run again. Set: the way back to the start is blocked
  (it names the move and what touches). Report it. The program can then be run ONCE: it ends away from its start, and rw2
  refuses a second run until the robot is moved back.
  There is no override for it; step 6 is for seams only.
- a seam's `notApplied`: values of the seam that the program does not use, in words. Report them once; they are not errors.
- a section with `reversed` true is welded from the seam's end to its start. That is allowed.

Report `planningSeconds`, `checks`, and how many seams are `Planned`, `Unreachable`, `NeedsValue`.

## Step 6. An unreachable seam

rw2 has already tried every torch orientation, every carriage stop it knows and welding the seam in reverse; when the blocked
move is the one coming from the seam before, it has also tried another posture for that seam. `Unreachable` is what is left
after that. The seam's `failure` describes the attempt that got furthest:

- `role`: which part of the seam's motion: `approach`, `weld`, `retract`, `transition` (the move across to the seam) or `track`
  (the carriage move before the seam).
- `move`: `Pose` = the arm cannot stand at that point; `Lin` or `Joint` = the move to it is blocked; `Track` = the carriage move
  is blocked.
- `contacts`: the two things that touch, or come too close: `a ↔ b` touches; `a ↔ b (12.3 mm)` is nearer than `clearanceMm`.
- `ikRefusal`: why the arm cannot reach, when `move` is `Pose`.
- `heldFrom`: on a `Track` failure, the seam welded just before the carriage move. The arm keeps that seam's retract posture
  while the carriage travels.
- `stopsTriedMm`, `orientationsTried`: what was tried.

Give ONE override and call `create_program_from_seams` again with the same arguments plus
`overrides` = `[ { "seam": "<seam>", "member": "<member>", "value": <number> } ]`, adding `"section": <index>` only where the table
says so. `seam` is the seam's full name exactly as the answer writes it (`pl-…/name`). Sections are numbered from 1.

Find the row by `role` and `move`. It does not matter whether the contact touches or carries a distance in brackets: with a
clearance a blocked move is reported at the first place it comes too close.

| `role` | `move` | `seam` to change | `member` | `value` |
|---|---|---|---|---|
| track | Track, with `heldFrom` | the seam in `heldFrom` | `retractMm` | 200; still failing: 300 |
| track | Track, no `heldFrom` | none | none | the first carriage move from the start is blocked: report it |
| approach or transition | Joint | the failing seam | `approachMm` | 200 |
| approach | Lin | the failing seam | `approachMm` | 50 |
| retract | Lin | the failing seam | `retractMm` | 50 |
| any | Pose, with `ikRefusal` | the failing seam, `section` 1 | `trackMm` | a carriage stop nearer to the seam than those in `stopsTriedMm` |
| weld | Lin | none | none | every orientation was tried: report the seam and its `contacts` |
| any | Pose without `ikRefusal` | none | none | every orientation and stop was tried: report the seam and its `contacts` |

Several seams often fail for one cause (the same `heldFrom`): one override repairs them all. Repair one cause at a time and read the
new answer before the next. An override stays in force on every later create. If a seam is still `Unreachable` after two
overrides, leave it, report its last `failure`, and go on to step 7 with the seams that are planned.

## Step 7. Run

Run right after step 5 or 6. Do not move the robot or the carriage in between: the plan starts from where they stand.
No compile step is needed.

1. rocketwelder `run_program` with the `programId`, `dryRun` = false. Leave `fromStart` out. Write down the run id the answer
   prints as `Run Id`.
2. rocketwelder `wait_for_run` with `programId`, `runId`, `timeoutSeconds` = 600.
   If it answers `Still running after 600 s`, call it again with the same arguments, as often as needed.
   A long part takes a long time: at 8 mm/s one metre of weld is about two minutes, plus the moves between seams.
   If the run ends `Failed` or `Cancelled`, report the block it stopped at and its message, and stop. Do not start another run:
   the robot is no longer where the program starts.

## Step 8. Seam verdicts

rocketwelder `get_seam_verdicts` with `id` = the `programId` and `runId`. If it answers 202 `pending`, wait two seconds and call again
(at most five times).

Each seam has a `verdict`:

- `Done`: the weld bead covers the whole seam.
- `NotDone`: in `passes`, `coveredMm` of `lengthMm` is covered. With `missing` = `["plan"]` the seam was not in the program
  (it was `Unreachable` at create).
- `NeedsValue`: `missing` names what was not available.

## Step 9. Report

Report: seams planned / unreachable, planning seconds and checks, the overrides you gave and why, the run's outcome and time,
and seams `Done` of all seams. List every seam that is not `Done` with its `failure` or its `coveredMm`.
