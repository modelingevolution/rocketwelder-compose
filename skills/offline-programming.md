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
   The station brings its own tools: `start_program_from_seams`, `wait_for_program_from_seams` and the others named below
   appear in the tool list only AFTER a station is selected. If they are missing after that, stop and report it: the station's
   rw2 is too old for this skill.
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
   If the person gave no speed: do NOT set one and do not invent one. Skip this step. Step 5's answer then says which speed the
   welds will run at; read it there.
   If it answers `ProgramEtagMismatchException` (HTTP 409), the program changed since the etag was read: repeat 1 and 2 with the
   fresh `etag`.

`Move.Travel` is the speed of the weld moves. The approach and retract lines and the moves between seams run at the
non-welding speed (`MovePtp.Travel`); leave it as it is unless the person says otherwise.

## Step 5. Create the program from the seams

Creating takes minutes (a part with twenty seams: twenty to thirty-five). So it is started, then waited for.

1. rocketwelder `start_program_from_seams` with:

- `id` = the `programId`
- `placements` = the labels from step 2, as a list (for example `["part/door-a"]`)
- `clearanceMm` = the clearance the person gave for THIS cell: the robot, the tool and the torch stay this far from the
  fixtures, the cell and other parts. None given: leave it out. The answer then carries a warning that names the value used;
  report that warning, do not pick a value yourself.
- Only if the person gave them, otherwise leave them out: `verdictToleranceMm`, `restartOverlapMm`, `partClearanceMm`,
  `jobNumber`, `arcStartHoldS`, `craterDwellS` (the welding machine's job and holds), `onePassMaxMm`, `backStepOverMm`,
  `backStepMm` (how long seams are cut: they depend on the material), `endPushDeg`, `endShortMaxMm` (how a seam ends against
  another member).

  It answers at once: `Planning started: N seams`. If it refuses, read the text: a wrong value is named; `already running`
  means a create of this program is in progress: go to 2, do not start another.

2. rocketwelder `wait_for_program_from_seams` with `id` = the `programId` and `timeoutSeconds` = 600.
   - `ended` false: the `message` says `Still planning after … s: seam i of M` (or `Still checking the program's moves`). Call it
     again with the same arguments, as often as needed. Do not start a second create and do not cancel.
   - `ended` true: `statusCode` 200 means the program is written and `answer` holds the result; read it as below. Any other
     `statusCode`: nothing was written; `answer` holds the refusal: report it and stop.

   In `answer`, every seam has an `answer`:

- `Planned`: nothing to do.
- `NeedsValue`: `missing` names the value. Ask the person for it; start again with it.
- `Unreachable`: go to step 6 for that seam.

Also read:

- `welding`: the speed the welds will run at, the job and the holds, in words.
- `warnings`. Each is a sentence; report every one. Three need action:
  - `welding speed NOT SET`: STOP before step 7, ask the person for the welding speed (a new program is then needed: step 3).
  - `clearanceMm not given …`: report it; ask the person whether that value is the cell's.
  - `corners to close by hand: …` and `seams not welded by the program: …`: this is the hand-work list. Copy both into your
    report word for word.
- `causes`: the refused seams grouped by what stopped them, with a count and one `next` per group. Use it in step 6.
- `returnFailure`. Null: the program ends where it started. Set: the way back is blocked; report it. The program can then be run
  ONCE; rw2 refuses a second run until the robot is moved back. There is no override for it.
- a seam's `notApplied`: sentences about how the seam is welded (sections, ends, corners, angles). Report the ones that say
  `corner open`, `work angle applied` or `refused`.
- a section with `reversed` true is welded from the seam's end to its start. That is allowed.

Report `planningSeconds`, `checks`, and how many seams are `Planned`, `Unreachable`, `NeedsValue`.

To create again (step 6), call `start_program_from_seams` again with the same arguments plus the override, then wait again.

## Step 6. An unreachable seam

rw2 has already tried every torch orientation, the carriage stops it knows (stepping outward when the arm cannot reach) and
welding the seam in reverse. `Unreachable` is what is left. You do not compute anything: the answer says what to do.

For each group in `causes` (one cause often stops several seams), read its `next`:

- `action` = `override`: it names `seam`, `member`, `value` and sometimes `section`. Start the create again (step 5) with the
  same arguments plus `overrides` = `[ { "seam": …, "member": …, "value": …, "section": … } ]` exactly as given. ONE cause at a
  time; read the new answer before the next. An override stays in force on every later create.
  Exception: when `member` is `workAngleDeg` the `reason` says it changes how the seam is welded. Do NOT apply it unless the
  person has said such values may be changed: report it with the seam.
- `action` = `report`: nothing a caller can change. Report the seam with the `reason`, its `contacts` and `closest`.

Each create again takes as long as the first. If a seam is still `Unreachable` after two overrides, leave it and go on to step 7 with the seams that are planned. The seams
left are in the warning `seams not welded by the program`.

## Step 7. Run

Run right after step 5 or 6. Do not move the robot or the carriage in between: the plan starts from where they stand.
No compile step is needed.

1. rocketwelder `run_program` with the `programId`, `dryRun` = false. Leave `fromStart` out. Write down the run id the answer
   prints as `Run Id`.
2. rocketwelder `wait_for_run` with `programId`, `runId`, `timeoutSeconds` = 600.
   If it answers `Still running after 600 s`, call it again with the same arguments, as often as needed.
   A long part takes a long time: one metre of weld at 8 mm/s is about two minutes, plus the moves between seams.
   If the run ends `Failed` or `Cancelled`, report the block it stopped at and its message, and stop. Do not start another run:
   the robot is no longer where the program starts.

## Step 8. Seam verdicts

rocketwelder `get_seam_verdicts` with `id` = the `programId` and `runId`. If it answers 202 `pending`, wait two seconds and call again
(at most five times).

Each seam has a `verdict`:

- `Done`: the weld bead covers the whole seam.
- `NotDone`: in `passes`, `coveredMm` of `lengthMm` is covered; `missing` says why. `short by plan: corner open N mm …` is
  expected: it is a corner from the hand-work list. `plan` means the seam was not in the program (it is in
  `seams not welded by the program`). Anything else: report it as a failure of the run.
- `NeedsValue`: `missing` names what was not available.

## Step 9. Report

Report: seams planned / unreachable, planning seconds and checks, the `welding` statement and every warning word for word (the
hand-work list above all), the overrides you gave and why, the run's outcome and time, and seams `Done` of all seams. Then
check one thing and say the result: every seam that is not `Done` must be either a corner in `corners to close by hand` or a
seam in `seams not welded by the program`. A seam that is in neither list is a failure: name it.
