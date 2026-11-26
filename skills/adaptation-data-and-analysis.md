---
name: adaptation-data-and-analysis
description: Read what an adaptation run did, judge whether its correction is good, and collect exactly what to send to RocketWelder when it is not. Covers the view photos, overlays and projections, the run's result and review, the tolerance bands and the limits of the solve.
triggers: [adaptation result, adaptation data, adaptation dataset, is the correction good, adaptation blocked, adaptation review reason, tolerance band, view overlay, view projection, send adaptation data, adaptation photos]
---
# Adaptation data and analysis

How a view, a mark and a correction are set up is in the skill `adaptation-setup` (`load_skill`). This skill reads and judges
what is already there. Every tool here is a read. You never move the robot, and never pass `confirmRealRobot`, on any
tool: the station's name in it lets a move through on a `Real` station. You never capture, add or re-take views, and
never mark points: the person does that on the adaptation page (`adaptation-setup`).

## Was the correction good?

Read `get_adaptation_result` for the run, then answer with this checklist. A correction is good when all hold:

1. The verdict is `auto-accepted` or `accepted`, and the reason (if any) is understood.
2. Every point marked in a view is found in that view (`points` solved, no NOT FOUND on the run page).
3. `settled` is true.
4. Per axis X/Y/Z: `Corrected` with its mm, or `NotCorrected` / `Unknown`, which are never a measured 0. The corrected
   axes and their mm match what the person sees: how far, and in which direction, the part really lies from
   where it was taught.
5. On the view overlays the green cross sits on the feature. A cross far from its blue ring means the part, or the mark,
   moved since teaching.
6. The weld lands on the seam. This is the final check, and only the person can see it.

A view whose `get_views` column `Stale` is true was taken under an older camera calibration. Before judging anything that
view measured, the person re-captures it (`adaptation-setup`: Move joint, then Re-capture).

## The data

| What | Tool / page | Answers |
|---|---|---|
| The block's views as stored | `get_views` (`programId`, `blockId`) | per view: id, enabled, joints (degrees), camera pose, `Stale` (taken under an older camera calibration), photo URL. Per mark: pixel, kind, correction |
| A view's reference photo | `get_view_photo` (`programId`, `blockId`, `viewId`) | the JPEG as taken, no marks |
| A view's photo with the marks | `get_view_overlay` (same) | PNG: green cross = the mark, blue ring = the taught point projected, orange diamond = where the editor draws the point now |
| The same as numbers | `get_view_projection` (same) | per point: taught position (mm), mark (px), projection (px), drawn position (px), mark-to-projection distance in px and, with a correction, in mm |
| The live camera with the points | `get_live_overlay` / `get_live_projection` (`id` = program id) | the live frame with each point in the frame drawn at the live arm pose (points hidden by their external axes are skipped); `inFrame` per point |
| The block's tolerance bands | `get_block_values` (`programId`, `blockId`) | `offsetTolerance`, `pathTolerance` and the layer each comes from (block, program, builtIn) |
| A review waiting now | `get_pending_review` (`programId`, `runId`) | the reason code and sentence, the proposed fit, its residual, per point found or not |
| What a run's adaptation did | `get_adaptation_result` (`programId`, `runId`) | per block: correction per axis, passes, settled, anchors, points, adapted path points, verdict |
| A run's progress | `get_run_progress` (`programId`, `runId`) | per block state, start and end |
| Run ids | `get_program_status` (`programId`) | the run id only while a run is in progress. A finished run's id: the answer of `run_program`, or the page `/program-executions`, where the run's id is in the address of its page |
| A run's photos, per block and view | page `/program-executions/<run id>`, then its adaptation row; or directly `/program-executions/<run id>/adaptation?block=<block id>` (add `&occurrence=<n>` for a block that ran more than once) | each view's live photo of the run, the points found (px, confidence) or NOT FOUND, the correction, the judgement |

The run's data is the **adaptation dataset**. RocketWelder writes it at every run, unless the camera's setting **Save
adaptation data for feature improvement** is off. It is pruned oldest first when it grows above its size limit (2048 MB as
shipped). `get_adaptation_result` answering 404 "no adaptation record" means the run wrote no data: the camera's setting
was off, the station-wide switch `AdaptationDataset:Enabled` was off, the free disk was below 1024 MB
(`AdaptationDataset:MinFreeDiskMb`), the run had no adaptation block, or the record was pruned.

## Reading a result

`get_adaptation_result`, per block:

- **correction** per base axis X, Y, Z: `Corrected` with its mm, `NotCorrected` (no anchor wrote it) or `Unknown` (no
  anchor observed it). `NotCorrected` and `Unknown` carry no number. They are never a measured 0.
- **passes** and **settled**: the solve repeats until a pass changes nothing by more than 0.01 mm, at most 5 passes (station
  settings `AnchorCorrection:FixpointThresholdMm`, `MaxPasses`). `settled: false` gives the review reason `no_fixpoint`.
- **anchors**: per anchor the view, the point, the order, what it wrote (mm) and its **residual** (mm), or its failure.
- **points**: taught → solved position (mm, robot base).
- **targets**: each adapted path point, taught → corrected pose.
- **verdict.kind**:

| Kind | Meaning |
|---|---|
| `auto-accepted` | below the accept limit: applied with no click |
| `accepted` | the person pressed Accept in the review window |
| `rejected` | the person closed the review window: the block stopped |
| `unwatched` | a review was needed but nobody watched the run: the proposal was applied |
| `readapt` | the person asked for the block to be adapted again |
| `blocked` | above the block limit: that block stops (blocks before it may already have welded) |

- **verdict.judgement**: the measured `offset` and `path` (mm), both bands, the verdict and its `trigger` (offset or path).
  For a block with anchors it also carries per-axis values and the `triggerAxis`.

## The tolerance bands

A band is written `accept:review` in mm.

- measured **< accept**: accepted with no click
- **accept ≤ measured ≤ review**: the person reviews
- measured **> review**, or not measurable: **blocked**

| Band | What it measures | Built-in default |
|---|---|---|
| `offsetTolerance` | how far the part moved | `10:10`: below 10 mm accepted, exactly 10 reviewed, above 10 blocked |
| `pathTolerance` | how much the correction deforms the path (the seam bent) | `inf:inf`: never reviewed or blocked |

Per axis, only `Corrected` axes are judged. The worst axis gives the verdict. A band comes from the block, the program's
defaults (`get_program_defaults`) or the built-in default. `get_block_values` shows which one is in force.

Raising a band is the person's decision, made in the program editor. Use `set_block_value` only when the person asks for it.

## Review and block reasons

Read the reason's sentence to the person: it names the points and numbers. The main codes:

| Code | Meaning | What to look at |
|---|---|---|
| `tolerance_band` | the offset or bend is in the review or block zone | the measured mm against the band. A real move of the part: re-seat it and adapt again. To weld at that offset, the person raises the band (`offsetTolerance` or `pathTolerance`) in the program editor; that change is recorded with the program. A blocked block stops; blocks before it may already have welded |
| `point_not_found` | a point was not found in the views that mark it | the run page's adaptation row (NOT FOUND) and `get_view_overlay`: lighting, the mark, the part in the frame. A view with `Stale` true: the person re-captures it (`adaptation-setup`: Move joint, then Re-capture) and marks again |
| `not_located` | a group of anchors located nothing | the same as `point_not_found`, for the whole group |
| `no_fixpoint` | the passes did not settle within 5 | the anchors with the largest residuals |
| `anchors_too_close` | a group's anchors are less than 10 mm apart in the direction that shows a turn (`AnchorCorrection:MinAnchorBaselineMm`): the group slides by the mean, with no turn | the anchors' positions. Anchors further apart give a turn |
| `axis_not_corrected`, `axis_unknown` | no anchor wrote or observed an axis. Only when `AnchorCorrection:UnobservedDirectionForcesReview` is on (off as shipped) | whether that axis matters for the weld |
| `orientation_tilt_exceeded` | an individually moved point would tilt the torch more than 10° (`AdaptOrientation:MaxTiltDeg`): refused, never clamped | the point's solved position against its neighbours |
| `found_ray_shallow` | the camera's ray meets the point's plane at less than 15° (`AnchorCorrection:MinRayToPlaneDeg`) | the view's angle to that face: a view looking more squarely at the face |

Other codes have their sentence. Read it as written.

## What to send us when the correction is not good

Collect these and give them to the person as one message to send to their RocketWelder contact:

1. The rw2 version: the person opens `<station address>/version` in a browser (`version`, `gitSha`).
2. The program id, the Adaptation block id and the run id.
3. The text answer of `get_adaptation_result` for that run.
4. The text answer of `get_views` for the block.
5. The text answer of `get_view_projection` for every view of the block.
6. The text answer of `get_block_values` for the block.
7. If a review waited: the text answer of `get_pending_review`.
8. The images: per view, the screenshot of `/program-executions/<run id>/adaptation?block=<block id>`, and the photo from
   `get_view_overlay`. `get_live_overlay` with `savePath` saves the live frame to a file.
9. What the person saw: where the weld landed against the seam, in mm and direction, and what was different about the part.

The photos show the part: the person decides whether they may be sent.
