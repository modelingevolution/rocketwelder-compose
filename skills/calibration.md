---
name: calibration
description: Guide a person through calibrating a station's camera in its order — lens, then joint corrections, then camera position (hand-eye). Covers what each one is, the page, the reads, what a good result looks like, what goes stale after a new calibration, and what to send to RocketWelder. The person runs every wizard. You read and explain.
triggers: [calibration, calibrate camera, lens calibration, intrinsics, joint corrections, joint offsets, hand-eye, camera position, accuracy at the tip, recalibrate, calibration changed, health check]
---
# Camera calibration

## The three calibrations

A camera is calibrated in three independent steps, **in this order**. Each step uses only the results of the steps before it.

| # | Step | What it finds | Robot moves | When |
|---|---|---|---|---|
| 1 | **Lens** | the camera's lens: fx, fy, cx, cy (px) and distortion k1, k2 (k3, p1, p2 stay 0) | no: the person holds the board in front of the camera | a new camera, or a change to the lens, focus, aperture, zoom or picture size |
| 2 | **Joint corrections** | the robot's joint offsets Δθ2..Δθ5 (degrees) | yes | rare: after installation, a crash, a motor or encoder change |
| 3 | **Camera position** (hand-eye) | where the camera sits on the tool | yes | after step 1 or 2 changed, or the camera was moved or re-mounted |

The **photos** of the board estimate. The **tip touches** (the torch tip touching board corners) only judge the result. They
never enter a solve.

## Rules

- **You never move the robot.** Never start, resume or retake a calibration run on a station whose kind is `Real`
  (`list_stations`). The person does it on the page, and confirms every robot move there. Every move is checked in the
  twin first.
- Never pass `confirmRealRobot`, on any tool.
- `upload_camera_calibration`, `restore_calibration_record`, `set_calibration_photo_timing` change the station. Use them only
  when the person asks, and say what they will write first.
- Lengths are mm, angles degrees, pixels px.

## Where it is

- Page **Commissioning → Calibrations**: `/commissioning/calibrations` (phone: `/mobile/commissioning/calibrations`).
- The **Camera set-up** card has one row per step: **1 Lens**, **2 Joint corrections**, **3 Camera position**. Each row
  shows its state and has its button: **Calibrate the lens**, **Correct the joints**, **Calibrate the camera**.
- A step that needs the lens first shows "needs 1 · Lens". The camera position row shows "calibrate again: the lens changed
  on …" or "calibrate again: the joint offsets changed on …" when an earlier step changed after it.
- The wizards: lens `/calibrate-lens/<camera>`, joint corrections `/calibrate/<camera>/1?joints=true`, camera position
  `/calibrate/<camera>/1?handEye=true`. On a phone, the same with `/mobile` in front.

## Step 1. Lens

1. The camera must stream. If it does not, the page says "Camera not streaming — start a pipeline first".
2. The person holds the board in front of the camera and presses **Take photo**. The photo is taken when the picture stops
   moving ("HOLD STILL…"). A photo is kept when the board's markers are read and at least 16 corners are found.
3. More photos: the board at several tilts (both ways), rolls and distances around the working distance, with corners
   reaching every edge and corner of the picture. The page says where corners are still needed.
4. **✔ ENOUGH PHOTOS** appears when at least 3 photos are kept and the lens uncertainty is within the corner noise.
5. **Find the lens**, then **Save as <camera>'s lens**. Saving the lens means the camera position must be calibrated again.

A good result: the card shows "picture fit <n> px", from the solve's reprojection RMS. Compare it with the corner noise the
page showed.

## Step 2. Joint corrections

1. **Correct the joints**. The person aims the camera at the board and touches 4 corners with the tip. Then the robot takes
   its photos on its own, each move confirmed on the page. A run can reuse the touches and photos of a camera calibration,
   as long as the board has not moved since.
2. The result is written **only** when "✔ THE CORRECTIONS IMPROVE ACCURACY AT THE TIP" appears. That needs the tip to be
   better by more than the touches' own scatter, and more than the corrections' own uncertainty.
3. Otherwise the page says, for example, "Better by only <x> mm: not more than your touches' own scatter, <y> mm. Nothing is
   written.", and the robot keeps its configured offsets. The card then reads "last run …: the robot's joint offsets kept".

The card shows "written … · joint check at the tip <mm>" when offsets were written, and "configured offsets in use" when
the step never ran.

## Step 3. Camera position (hand-eye)

**Calibrate the camera** opens the wizard. It needs a robot.

1. **Aim**: the person jogs until the camera sees the board, then **Take photo ◉**.
2. **Three poses**: the robot drives three short moves, with a photo at each.
3. **Four corners** (optional): **Go above corner N**, then the person touches the corner with the tip and presses
   **Tip is on ★**. **Skip the touches** is allowed: the calibration does not need them, but it then has no accuracy at
   the tip.
4. The **tour**: the robot drives the poses the planner offers and takes photos. It stops when another photo no longer
   improves the predicted precision.
5. **Save** (or **Discard**). Nothing is written to the robot.

A good result is the **Accuracy at the tip** from the touches: typical (RMS) and largest, in mm. The photos' predicted
precision is only the planner's goal, not an accuracy. Without touches the card says "not measured: no tip touches in
this calibration".

## Reads

| Read | Tool |
|---|---|
| The calibration in force: lens, camera→TCP, joint offsets, RMS, validated, revision | `get_camera_calibration` (`name` = camera) |
| Every saved calibration, oldest first, in force or not, restorable | `list_calibration_records` (`name`) |
| One record with its values | `get_calibration_record` (`name`, `revisionId`) |
| Every wizard's runs, newest first: kind (which wizard), state, step, photos, best S, whether it can resume and why not | `list_calibration_runs` (`name`) |
| The calibration photo timing (wait after the arm stops, frames skipped) | `get_calibration_photo_timing` |
| Health checks (is the calibration still good?): verdict `GoodToGo`, tolerance, the camera and TCP parts | `list_health_checks`, `get_health_check` |
| Marker and TCP checks behind a health check | `list_marker_checks`, `get_marker_check`, `list_tcp_checks` |
| The live picture | `get_camera_frame` |

Two run tools only open a page. The person continues there:

- `resume_calibration_run` reopens an unfinished run. Nothing moves. It is refused with a code word: `run-open`,
  `run-saved`, `no-lens-data`, `no-solvable-photo`, `board-moved-since-corners` or `validation-run`.
- `retake_calibration_poses` opens a new run that retakes a record's photo poses. Nothing moves until the person starts it
  on the station. At the end the page compares the old run with the retake.

On a `Real` station, do not call them: the person resumes the run from the Calibrations page, or uses **Retake from
old poses** there.

Photos look blurred or late (the picture lags the arm): raise the wait with `set_calibration_photo_timing`, when the person
asks. It applies to calibration photos only, station-wide.

## After a new calibration: what goes stale

- **The camera position** goes stale after a new lens or new joint offsets. The card says "calibrate again: …".
- **Adaptation views** taken under an older calibration: the `get_views` column `Stale` is true when the camera or lens
  changed. It does not show a change of the joint offsets alone: such a view still reads `Stale` false, yet the program's
  dialog still asks about it and a run is refused ("Refusing to run: the views were
  taken before the calibration changed: …") until the views are repaired. When the program opens, the
  page asks "The calibration has changed": since these views were taken, was the camera moved or re-mounted?

| Answer | What it does |
|---|---|
| **Camera moved or re-mounted** | keeps the photos and marks, and changes where the robot stands at each view |
| **Camera not moved** | keeps the photos, marks and joints, and changes only the stored camera positions |
| **Not sure — take new photos** | sets the photos aside. Each view is taken again and marked again |
| **Not now** | nothing changes. The question comes back when the program is opened again |

After a new lens, only new photos are right: choose "Not sure — take new photos".

After new joint offsets, the camera position must be calibrated again first: the person runs **Calibrate the camera**
(step 3), and only then opens the programs. If the camera really did not move, the answer is then "Camera not moved".
The dialog may offer "Camera not moved" for a joints-only change before step 3 has run: do not answer it until step 3 is
done.

The program cannot check the answer. A wrong one makes adaptation place the part
wrong. Re-taking a view: skill `adaptation-setup`.

## What to send us

Collect these and give them to the person as one message to send to their RocketWelder contact:

1. The rw2 version: the person opens `<station address>/version` (the version `register_station` showed is from when the
   station was registered).
2. The camera name, and the text answers of `get_camera_calibration`, `list_calibration_records` and `list_calibration_runs`.
3. For the run in question: its run id (`cs-…`) and `get_calibration_record` for the revision it saved.
4. A screenshot of the wizard's result screen (picture fit, accuracy at the tip, the touches' scatter).
5. The newest `get_health_check`, if one was run after the calibration.
6. What changed on the cell before the calibration: a new camera, lens, focus, a crash, a re-mount, a new tool.
