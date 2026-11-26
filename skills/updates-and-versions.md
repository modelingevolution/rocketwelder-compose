---
name: updates-and-versions
description: Which RocketWelder version runs on this station, whether an update is available, how the operator applies it, what a failed or rolled-back update means, and what to report to RocketWelder.
triggers: [which version, what version runs here, is there an update, how do I update, update failed, update rolled back, AutoUpdater, upgrade available]
---
# Updates and versions

## The three versions

| Version | Looks like | What it is | Where the person reads it |
|---|---|---|---|
| rw2 (the welder application) | `2.93.0` | The RocketWelder program serving the station UI and this MCP | Station UI: bottom of the left menu, `v2.93.0`; hover shows the git sha. Browser: `<station url>/version` answers `{ version, gitSha, source }` |
| Station release (compose) | `4.0.220` | The release the AutoUpdater installs. It pins one rw2 version and carries the skills | AutoUpdater page, the RocketWelder package: "Current version" |
| Claude bundle (`mcp-rocketwelder`) | `1.0.0` | The program on the person's computer that connects Claude to the station | Claude Desktop, the installed RocketWelder extension |

A station release names its rw2 version in its `rocketwelder.version` file:
`https://github.com/modelingevolution/rocketwelder-compose/blob/v<release>/rocketwelder.version`.

`register_station` also answers the rw2 `version` and `gitSha`, at the moment the station is registered.

## The AutoUpdater

The AutoUpdater is the station's update service. Its page runs on the station's address, port 8080:
`http://<station address>:8080/`. Claude cannot open it; the person opens it in a browser.

Each package on the page is a card:

| Card element | Meaning |
|---|---|
| Name | The package. The RocketWelder package is named after its install folder (`rocket-welder` when installed with the AutoUpdater's `install.sh`) |
| Current version | The installed station release |
| Status line | `Current version: X`, `Upgrade available: X`, `Checking for updates...`, a progress line during an update, or the error of the last update |
| Check Package Version button | Fetches the release tags and shows whether a newer release exists |
| Update package button (run icon) | Installs the newest release. Disabled with "No update available" when there is none |
| Backup button | "Manage Backups": the backups taken before updates, each with Restore |

"Update all" below the cards runs Update on every package on the page. Use the RocketWelder card's own Update button. During any update the update log appears under "Update all".

## How updates behave

- **Nothing updates by itself.** The AutoUpdater checks for a newer release once when it starts and when someone clicks Check Package Version. It installs only when the operator clicks Update.
- **An update restarts the welder.** It stops every service of the station (`docker compose down`) and starts them again, even when only skills changed. Update only when no program is running and nobody is welding. To check, call `get_program_status` for the program in use and confirm it is not `Running`.
- **Skills arrive with a station release.** A new or changed skill is served after the update that carries it. `list_skills` shows the result.
- **The newest release wins.** Update always goes to the highest release number; it does not offer a choice of version.

## Answering the common questions

| Question | Answer |
|---|---|
| Which version runs here? | Ask the person for the rw2 version at the bottom of the station's left menu (or `<station url>/version`) and the station release from the AutoUpdater card. |
| Is there an update? | The person opens `http://<station address>:8080/`, clicks Check Package Version on the RocketWelder card, and reads the status line: `Upgrade available: X` or `Current version: X`. |
| How do I update? | Confirm nothing runs, then click Update package on the RocketWelder card. The status line shows the progress; the station UI is unavailable while the welder restarts. Afterwards the status line shows `Current version: <new release>`. Check the new rw2 version in the station UI. |
| My Claude does not know a new skill | The skill came with a release that is not installed yet: update the station. After the update, call `list_skills` again. |

## A failed update

The card's status line shows the error and the card stays in an error state. The messages:

| Message | Meaning |
|---|---|
| `Migration failed: <reason>` | A migration script of the new release failed. With a backup, the AutoUpdater rolled back: services stopped, data restored from the backup taken before the update, services started |
| `Migration failed: <reason> - No recovery possible without backup` | As above, but no backup existed, so nothing was restored |
| `Docker startup failed: <reason>` | The services did not start on the new release. With a backup, the same rollback ran |
| `Docker startup failed: <reason> - No recovery possible without backup` | The services did not start and nothing was restored |
| `Critical services unhealthy after deployment` | The new release started but a critical service is unhealthy; a backup existed, so the rollback ran |
| `Partial deployment - some services unhealthy` | The new release is installed and recorded as current, but some services are unhealthy (no rollback) |
| `Unexpected error: <reason>` | The update stopped on an error; with a backup, the rollback ran. `Rollback failed: <reason>` added means the rollback also failed |
| `Update already in progress` | Another update is running; wait for it |

After a rolled-back update the card still shows the previous release as Current version. Do not retry the update in a loop; report it.

## What to report to RocketWelder

Send all of these:

1. rw2 version and git sha (station UI menu, or `<station url>/version`).
2. Station release: Current version and the available version from the AutoUpdater card.
3. The exact status-line message after the update.
4. The update log shown under "Update all" during the update, copied or photographed in full.
5. The time of the update and whether a program was running.
6. The Claude bundle version, when the problem is in Claude's connection to the station.

## Missing read tools

Claude cannot read these itself. Until the tools exist, the person reads them as above.

| Tool | Effect | Endpoint | Owner |
|---|---|---|---|
| `get_station_version` | read | rw2 `GET /version`, marked `.ForAgents("get_station_version", ToolEffect.Read)` | rw2 |
| `get_station_updates` | read | AutoUpdater `GET /api/upgrades/{packageName}` (current and available release) on port 8080, reachable through the rocketwelder MCP | AutoUpdater + mcp |
