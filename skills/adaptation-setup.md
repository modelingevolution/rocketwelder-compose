---
name: adaptation-setup
description: Guide a person through setting up adaptation for a part on a RocketWelder station. Covers the views, the intermediate positions, the photos, marking the points (and marks or circles that do not show), the correction of each point, the review window, a test run, and how to judge the result. The person moves the arm and takes the photos. You read and explain.
triggers: [adaptation, set up adaptation, adaptation views, view photo, photo, mark points, marks, mark not shown, circle, circle not shown, drew on the photo, marking tools disabled, station screen, intermediate position, wasted stop, reorder views, move joint, PTP to view, correction plane, adaptation review, review window, adaptation result]
---
# Setting up adaptation

## How adaptation works

A part never lies exactly where it lay when the program was taught. Adaptation measures where it lies now and moves the
program's points to match. It lives in an **Adaptation block** in the program.

- A **view** is a place the camera takes a photo from. It stores the arm's joints, the camera pose and a **reference
  photo**.
- On each reference photo the person **marks** where each point of the block is seen.
- At every run, before welding, the arm goes to each view by a **joint move to the view's recorded joints**, waits for the
  arm to settle, and takes a photo. RocketWelder finds every mark in the new photo. The difference from the reference photo
  is how far the point moved.
- The block's points are moved by that amount, only along the directions each point is set to correct (its **correction**,
  step 6). The torch keeps its angles to the seam: after the points move, each point's orientation turns with the adapted
  segment, so work, travel and roll angles to the seam stay as taught.
- The run then **accepts** the correction on its own, or opens a **review** for the person (step 8).
- An **intermediate position** is a stop between views with no photo. The arm only passes through it, usually to get round
  something. There is no settle wait and no photo.

## Rules

- **You never move the robot.** The person jogs the arm, presses Move joint, captures views and runs the program. You read,
  explain and check. Never call `run_program` or `decide_adaptation` on a station whose kind is `Real` (see `list_stations`).
- Never pass `confirmRealRobot`, on any tool. The station's name in it lets a move through on a `Real` station.
- A change tool (`set_point_correction`, `remove_point_correction`) changes the program. Use it only when the person asks,
  and say what it will write first.
- Units: mm and degrees. One exception: `get_robot_joints` answers in **radians**, while `get_views` gives the view's joints
  in **degrees**.
- A refusal is an answer: read it to the person. Do not repeat a refused call unchanged.

## Step 1. The program and its Adaptation block

1. `list_programs` → the program's id. `get_program_tree` → the Adaptation block's id.
2. UI: the program editor, `/teach/program/<program id>`. No Adaptation block yet: the person adds one from the block
   toolbox. In rw2 2.93.0 and later it goes directly above the selected block
   (never before a Touch sense). With nothing selected, the first one goes to the start of the program, or, when the
   program has a Touch sense, to the end of the list. So the person first selects the block it should go above.
3. The person opens the adaptation page with **Set up adaptation** (no views yet) or **Open adaptation**. Its address is
   `/teach/program/<program id>/adaptation/<block id>` (with `/views/<view id>` when a view is selected). The page title is
   "Adaptation — <program> · <n> views". Top left is the **Views** list, the picture is in the middle, and the toolbar is
   above the picture.

## Step 2. Capture the views (Camera mode)

The camera must be calibrated. If it is not, the page says "The camera isn't calibrated yet…". Calibrate first.

1. The person switches the picture to **CAMERA** and jogs the arm until the camera sees the block's points.
2. Check before the capture: `get_live_overlay` with the program id gives the live frame with each point that is in the
   frame (and not hidden by its external axes) drawn as an orange cross. `get_live_projection` gives the same as numbers:
   `inFrame` per point. A good view has `inFrame: true` for every point it should measure, and the person sees each
   feature on the frame.
3. With **New view** selected, the person presses **◉ Capture this view**. The photo is taken where the arm stands, and the
   arm's joints are recorded with it. The page then returns to Photo mode with the new photo.
4. More views: the person jogs to another angle and captures again. A point's height (depth) can be **triangulated** from its
   views. That needs at least 3 views of the point, a spread of at least 30° between their viewing angles, and rays that agree
   within 2 mm. The page shows "need ≥30° to triangulate" and "<n>° spread".
5. Check: `get_views` lists each view with its joints (degrees), `Stale` (taken under an older camera calibration) and its photo.
   `get_view_photo` shows the stored photo.

**Views are reached by joint moves only** (owner ruling). This rule is for adaptation views only: taught program points
keep their PTP and linear moves. **Move joint** drives the arm to the selected view's exact recorded joints. Never use PTP
or a linear move to reach a view. The status line reads "Arm at view <n>" when every joint is within 0.1°. A view with no
recorded joints (taken before joints were recorded) says "pose only — re-capture to record joints". For such a view Move
joint falls back to a pose move, so it is not reached by exact joints: the person presses Move joint once, then
Re-capture, and from then on the view has its joints. Under a touch-sensed height or plane the run moves a view with the
part, and then reaches it by a pose move.

**Re-capture** (**◉ Re-capture view <n>**) takes the photo where the arm stands now, and the view moves there. To keep the
view where it is, press **Move joint** first. After a re-capture from a new place, the marks on that view must be placed
again.

## Step 3. Intermediate positions

Use one where the arm needs a waypoint between two views, usually to avoid a collision.

1. The person jogs the arm to the waypoint and presses **⤳ Capture intermediate position**. It is inserted directly below
   the selected entry (at the end when New view is selected). It records the arm's joints and takes no photo.
2. Select it to **◉ Re-capture position** (the arm's joints now) or **Delete** it. Move joint goes to views only, so the
   person jogs to an intermediate position.
3. **▲ / ▼** (Move up / Move down) in the Views heading move the selected entry. The run follows the list order.
4. View numbers count views only. Intermediate positions have no number.
5. At run time the arm drives through an intermediate position by its exact joints, with no settle wait and no photo. It
   is never moved with a touch-sensed height or plane.

A view with no points, saved before rw2 2.93.0, stays a view: the run still settles there and takes a photo. To drop the
stop:

1. Select the view and press **Move joint**: the arm goes to its exact joints.
2. Press **⤳ Capture intermediate position**: it is inserted below the view, at those joints.
3. Remove the old view with the ✕ on its card ("Remove view <n>").
4. If needed, move the intermediate position with **▲ / ▼** so it stands where the old view stood in the list.

At run time the arm is then driven through it by its exact joints, with no settle wait and no photo.

`get_views` does not tell an intermediate position from a view with no points: both read `transit: true`. Use the page's
Views list for that.

## Step 4. Mark the points (Photo mode)

Marking is done on the stored photo, in **PHOTO** mode. Taps on the live camera picture do nothing. Selecting a view never
moves the arm.

| Tool | Gesture | Use for |
|---|---|---|
| Point | tap | a point that can be seen sharply |
| Circle · Center / Circle · Two-point | drag (a single click adds a plain point) | a hole or a round feature |
| Corner / Corner · Center | drag | a corner |
| Lines | two or more strokes along real edges, then Done | the point where edges meet |

- Each point has a type: **Moves the path**, or **Anchored — moves only itself**.
- Check every view: `get_view_overlay` returns the photo with, per point, the mark (green cross), the taught point
  projected (blue ring) and the drawn position (orange diamond). `get_view_projection` gives the same as numbers,
  including the mark-to-projection distance in px and, for a point with a correction, in mm.
- A good result: each mark sits on the feature, and its blue ring is close to the cross. A cross far from its ring means
  the part or the mark moved since teaching. Ask the person which one moved.
- Optional, **◈ Capture empty reference**: with the part removed, the empty fixture is photographed. Points are then found
  against it.

## Step 5. A view's photo is out of date

`Stale` true in `get_views` means the camera was recalibrated after the view was taken. The page says "Recapture
this view first — the camera was recalibrated". The person presses Move joint, then Re-capture, and marks again.
`Stale` covers the camera calibration only: a view taken under other joint offsets still reads `Stale` false, yet the
run refuses to start for it ("Refusing to run: the views were taken before the calibration changed: …"). The remedy is
the same: Move joint, then Re-capture.

## Step 6. The correction of each point

The correction says along which directions a sighting may move its point. In the page this is the point's **Plane** panel:
**Plane** (top, side ⊥Y, side ⊥X, Custom …), what it **moves** (X, Y, Z or across the line) and its **order** (lower first),
then **Save**. Unset values take the station's settings. The shipped default is the XY plane, moves X and Y, order 0. A
one-line point moves across the line.

Same by MCP, only when the person asks: `set_point_correction` with `programId`, `blockId`, `viewId`, `name`, and any of
`plane` (XY | ZX | ZY | Custom), `normal` (Custom only), `writes` (X, Y, Z, or Across alone), `direction` (instead of
`writes`), `order`. The answer is `Saved` or `Unchanged`. A 422 lists the broken rules, and nothing is written.
`remove_point_correction` goes back to the default.

A direction that no point observes is reported as **Unknown** or **NotCorrected**, never as 0. On a weld along an edge,
the position along the edge may legitimately stay uncorrected.

## Step 7. Test run

The person starts the run on the station. A simulator station only: you may run it yourself (`run_program`, then
`watch_run` so that reviews wait for an answer).

## Step 8. The review window

1. A point that was not found: the person marks it on the photo and presses **It is here** (**Reset** undoes it).
2. **✓ Accept and continue** applies the correction and welds.
3. Closing the window **rejects** it: the block stops.

The run screen opens this window when the correction is not accepted on its own. It shows the reason, every view's photo
with the points, and a row per point. A review waits for an answer only while a run screen (or a `watch_run`) holds the run
open. With neither, the run applies or refuses it on its own.

Read the review with `get_pending_review` (`programId`, `runId` of the running run from `get_program_status`): the reason
code and sentence, the proposed fit (tx, ty mm, rotation °), its residual, and per point whether it was found. Explain it.
On a `Real` station the person decides in the window. `decide_adaptation` is for simulator stations only.

## Step 9. Judge the result

`get_adaptation_result` reads what the run did, from its dataset:

- per axis X/Y/Z: `Corrected` with its mm, or `NotCorrected` / `Unknown`
- the verdict: accepted, auto-accepted, rejected, unwatched, readapt or blocked, with its reasons
- per anchor: view, point, what it wrote (mm) and its residual (mm)
- per point: taught and solved position

A good setup: the verdict is accepted or auto-accepted, every point is found in every view that marks it, and the
corrections match how far the part really moved. Repeat steps 4–6 for a point that is often not found or has a large
residual. Judging in detail: the skill `adaptation-data-and-analysis`.

## Labels in Polish

The station UI may be in Polish. The labels this skill names:

| EN | PL |
|---|---|
| Set up adaptation / Open adaptation | Skonfiguruj adaptację / Otwórz adaptację |
| Views / New view | Ujęcia / Nowe ujęcie |
| PHOTO / CAMERA | ZDJĘCIE / KAMERA |
| Move joint | Ruch przegubowy |
| ◉ Capture this view / ◉ Re-capture view <n> | ◉ Przechwyć to ujęcie / ◉ Ponów zdjęcie ujęcia <n> |
| ⤳ Capture intermediate position / ◉ Re-capture position / Delete | ⤳ Przechwyć pozycję pośrednią / ◉ Ponów pozycję pośrednią / Usuń |
| Move up / Move down | Przesuń wyżej / Przesuń niżej |
| Point, Circle, Corner, Lines | Punkt, Okrąg, Narożnik, Linie |
| Moves the path / Anchored — moves only itself | Przesuwa ścieżkę / Zakotwiczony — przesuwa tylko siebie |
| ◈ Capture empty reference | ◈ Przechwyć pusty wzorzec |
| Save | Zapisz |
| It is here / ✓ Accept and continue | To jest tutaj / ✓ Akceptuj i kontynuuj |

## Known faults

| Fault | What the person sees | What to do |
|---|---|---|
| bug-078, native player (station screen) before rw2 2.93.0 | The photo shows no points. All marking tools are disabled. The status line says "Mark points from a browser — this screen cannot show the view's photo for marking." (PL: "Punkty oznaczaj w przeglądarce…") | Mark in a browser, or update to 2.93.0 or later. |
| bug-082, Linux native player (station screen) up to v1.3.1 | One tap on the photo sometimes adds two points (the tap came while the photo's overlay was still starting) | Press Undo in the page head (one mark is one undo step), or delete the extra point. Fixed on native-player master, in the next native-player release. |
| bug-079, before rw2 2.93.0 | A circle (or any mark) does not appear after the drag. It appears after a page reload | The mark is saved. Reload (F5) and do not mark it again. |
| bug-080, before rw2 2.93.0 | A new Adaptation block lands at the top of the program, not above the selected block | Move it with the block's ↑ / ↓ to where it belongs. |

