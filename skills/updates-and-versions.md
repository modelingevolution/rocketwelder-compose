---
name: updates-and-versions
description: Which RocketWelder version runs on this station, whether an update is available, how the operator applies it, what a failed or rolled-back update means, what to report to RocketWelder, and why a new skill is missing (skills arrive with a station update).
triggers: [which version, what version runs here, is there an update, how do I update, update failed, update rolled back, AutoUpdater, upgrade available, skill missing, new skill not there, skill not listed, you don't know the new skill]
---
# Updates and versions

## The three versions

| Version | Looks like | What it is | Where the person reads it |
|---|---|---|---|
| rw2 (the welder application) | `2.93.0` | The RocketWelder program on the station: its UI and the REST routes this MCP calls | Station UI: bottom of the left menu, `v2.93.0`; hover shows the git sha. Browser: `<station url>/version` answers `{ version, gitSha, source }`; a build that is not a release answers `dev-<sha>` |
| Station release (compose) | `4.0.220` | The release the AutoUpdater installs. It pins one rw2 version and carries the skills | AutoUpdater page, the RocketWelder card: "Current version" |
| Claude bundle (`mcp-rocketwelder`) | `1.0.0` | The program on the person's computer that connects Claude to the station | Claude Desktop, the installed RocketWelder extension |

A station release names its rw2 version in its `rocketwelder.version` file:
`https://github.com/modelingevolution/rocketwelder-compose/blob/v<release>/rocketwelder.version`.

The rw2 version in the left menu is what runs. The card's "Current version" is the release the AutoUpdater last recorded; after a
failed update the two can disagree.

## The AutoUpdater

The AutoUpdater is the station's update service. Its page runs on the station's address, port 8080:
`http://<station address>:8080/`. Claude cannot open it; the person opens it in a browser.

Each package on the page is a card:

| Card element | Meaning |
|---|---|
| Name | The package. The RocketWelder package is named after its install folder (`rocket-welder` when installed with the AutoUpdater's `install.sh`) |
| Current version | The station release the AutoUpdater last recorded |
| Available upgrade: | Shown instead of the status line when a newer release is known |
| Status line | `Current version: X`, `Checking for updates...`, a progress line during an update, the error of the last update, or `Version check failed. Details are in the AutoUpdater log.` |
| Refresh icon (tooltip "Check Package Version") | Fetches the release tags and shows whether a newer release exists |
| Run icon (tooltip "Update package") | Installs the newest release. Disabled, tooltip "No update available", when none is known |
| Backup menu | "Create Backup" and "Manage Backups": the backups, each with Restore |

"Update all" below the cards runs Update on every package on the page. Use the RocketWelder card's own Update button. During an
update the update log appears under "Update all".

## How updates behave

- **Nothing updates by itself.** The AutoUpdater checks for a newer release once when it starts and when someone clicks the refresh icon. The available release is only as new as that last check. It installs only when the operator clicks Update.
- **An update restarts the welder.** It stops every service of the station (`docker compose down`) and starts them again, even when only skills changed. Update only when no program is running and nobody is welding. To check, call `get_program_status` for the program in use and confirm it is not `Running`.
- **Skills arrive with a station release.** A new or changed skill is served after the update that carries it. `list_skills` shows the result.
- **The newest release wins.** Update always goes to the highest release number; it does not offer a choice of version.
- **Claude changes nothing here.** Updating and restoring are the operator's clicks on the AutoUpdater page. An update is undone with the Backup menu → Manage Backups → Restore on a backup taken before it: that restores the data and checks out the release the backup was taken on.

## Answering the common questions

| Question | Answer |
|---|---|
| Which version runs here? | No tool reads the current version (`get_station_version` is missing; `register_station` reads it only when a station is registered). Ask the person for the rw2 version at the bottom of the station's left menu (or `<station url>/version`) and the Current version on the AutoUpdater card. Report both. |
| Is there an update? | The person opens `http://<station address>:8080/`, clicks the refresh icon on the RocketWelder card, and reads it: `Available upgrade:` with a release, or `Current version: X` when there is none. |
| How do I update? | Confirm nothing runs, then click the run icon (Update package) on the RocketWelder card. The status line shows the progress; the station UI is unavailable while the welder restarts. Afterwards the status line shows `Current version: <new release>`. Check the new rw2 version in the station UI. |
| A new skill is missing / not listed / Claude does not know it | Skills arrive with a station release. A skill not in `list_skills` is in a release this station has not installed: the operator updates the station (AutoUpdater), then call `list_skills` again. If the AutoUpdater shows no update, the skill is not released yet: tell RocketWelder. |

## A failed update

The card's status line shows the error until the next check. The messages:

| Message on the card | What happened |
|---|---|
| `Docker image pull failed: <reason>` | The new images could not be downloaded (registry or network). Nothing was stopped; the station keeps running |
| `Backup creation failed - cannot proceed: <reason>` | The backup before the update failed. Nothing was stopped |
| `Migration failed: <reason>` | A migration script of the new release failed. Rolled back: services stopped, data restored from the backup, services started |
| `Migration failed: <reason> - No recovery possible without backup` | As above, but no backup existed: nothing was restored |
| `Docker startup failed: <reason>` | The services did not start on the new release. Rolled back as above |
| `Docker startup failed: <reason> - No recovery possible without backup` | The services did not start and nothing was restored |
| `Critical services unhealthy after deployment` | The new release started but a critical service is unhealthy. Rolled back as above |
| `Partial deployment - some services unhealthy` | The new release is installed, some services are unhealthy, no rollback. The card keeps the old Current version |
| any other text | The update stopped on an unexpected error; the text is the error itself. With a backup, a rollback was attempted; whether it worked is only in the update log |

**After a rollback the station may run the failed release.** The rollback restores the data and restarts the services from the new
release's files, so the new rw2 can run on the restored data while the card shows the old Current version. Never assume the old
release runs: ask the person for the rw2 version in the left menu and report both values. Do not retry the update; report it.

## What to report to RocketWelder

Before anyone clicks anything on the AutoUpdater page: the refresh icon clears the error from the card, and every Check, Update and
Update all click clears the update log. Have the person copy or photograph both first.

1. The exact message on the RocketWelder card.
2. The update log under "Update all", in full.
3. rw2 version and git sha (station UI left menu, or `<station url>/version`).
4. The card's Current version and the release that was being installed.
5. The time of the update and whether a program was running.
6. The Claude bundle version, when the problem is in Claude's connection to the station.

## Missing read tools

Claude cannot read these itself. Until the tools exist, the person reads them as above.

| Tool | Effect | Endpoint | Owner |
|---|---|---|---|
| `get_station_version` | read | rw2 `GET /version`, marked `.ForAgents("get_station_version", ToolEffect.Read)` | rw2 |
| `get_station_updates` | read | AutoUpdater `GET /api/packages/installed` (each package's name and Current version, no git access). The available release, from `GET /api/upgrades/{packageName}`, is only as new as the last check. The MCP knows only the rw2 url; reaching the AutoUpdater on port 8080 needs a second address per station or an rw2 route that forwards to it, an owners' decision | AutoUpdater + mcp |
