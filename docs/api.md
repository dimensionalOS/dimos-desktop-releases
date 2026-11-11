# Desktop HTTP API

How do I ...? (notify, open an app, run a sudo command, events): [how-to.md](how-to.md).

One Rust process (`dimos-desktop serve`) on `http://127.0.0.1:<port>` (port from `~/.dimos/config.yaml`, default 5555).
JSON everywhere unless noted. Errors: non-2xx with `{ "error": "<message>" }`.

## `/dimos/` — the dimos tooling API

The only part of Desktop that depends on the dimos version. Apps (the Launcher included) use it instead of shelling out
to dimos. It is served by **the dimos gateway**, dimos's own process (dimos/gateway/) on a unix socket, which Desktop
proxies `/dimos/` to and starts on demand with the `start:` command of the `dimos.yaml` in the checkout at `dimos.dir`
(docs/install.md). Desktop itself only talks to dimos through it. Its full reference is its own OpenAPI document,
`GET /dimos/openapi.json`; the main routes:

| Method + path                 | Body / query                                   | Response                                                                                           |
| ----------------------------- | ---------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `GET /dimos/info`             |                                                | `{ dir, found, installed, version, range, inRange }`                                               |
| `GET /dimos/paths`            |                                                | `{ dimosDir, runsDir, logsDirs: [string], recordingsDir }`                                         |
| `GET /dimos/blueprints`       | `?fresh=1` (else cached 60s)                   | `{ blueprints: [{ name, kind: "builtin" \| "external", importable, ... }] }`                       |
| `GET /dimos/blueprints/:name` |                                                | `{ name, modules: [{ name, class, streams: [{ name, type, direction: "in"\|"out"\|"inout" }] }] }` |
| `GET /dimos/global-config`    |                                                | `{ schema, defaults, overrides }`. `schema` = JSON Schema of dimos's GlobalConfig                  |
| `PUT /dimos/global-config`    | `{ overrides: { key: value } }`                | same as GET. Overrides are saved in config.yaml and passed as `--key value` on every launch        |
| `GET /dimos/runs`             |                                                | `{ runs: [RegistryRun], launch: Launch \| null }`                                                  |
| `POST /dimos/runs`            | `{ blueprint, replay?: bool, overrides?: {} }` | `Launch`. `overrides`: `{ global?, modules? }` for this launch only (launcher.md#config)           |
| `POST /dimos/runs/stop`       |                                                | `{ output }`                                                                                       |
| `GET /dimos/runs/:runId/log`  | `?after=<offset>&level=<min>&q=<text>`         | `{ runId, records: [LogRecord], offset, loggers }` (`runId` may be `latest`)                       |
| `GET /dimos/healthz`          |                                                | `ok`                                                                                               |
| `POST /dimos/server/stop`     |                                                | `{ stopping: true }`: the server exits (Desktop starts it again when needed)                       |

When the dimos gateway can't be started, `/dimos/*` answers 503 `{ error }` saying why (and where its log is).

### The blueprint view

`/?view=blueprint&name=<blueprint>` is Desktop's own page (ui/src/blueprint_view/; before dimos gateway API 9.0 the
gateway served it at `/gateways/dimos/blueprint_view`): a blueprint's modules (rarest first) beside its module graph
(drawn from the wiring, with Desktop's `GET /gateways/desktop/topics/rates` on its topics while it runs), each module's
streams, skills, RPC methods and code, its config dialog, its logs and its processes. It reads the dimos gateway
(`catalog/blueprints/{name}`, `catalog/blueprints/{name}/source`, `catalog/modules/{class}/source?blueprint=`, `active`,
`active/stats`, `history/{runId}/logs`) and the Launcher (`config/global`, `config/blueprints/{name}`, `launch`,
`relaunch`), and follows the gateway's zenoh events (`launch`, `log`, `stats`). Its timers are Desktop settings,
`GET /gateways/desktop/settings`'s `blueprint-view:` (config.yaml, the keys the gateway read before): `rates-poll-s`
(2), `poll-without-events-s` (3) and `log-max-records` (5000), read again on a `settings` event. `&run=<runId>` shows
that run's logs, `&dialog=logs` opens on them, `&hidden=1` starts it paused. The bottom bar's Details frames it
(ui/src/shell/BlueprintDetails.tsx), loaded ahead and hidden. The page and its parent talk over postMessage on
Desktop's origin:

| From → to      | Message                                             | Meaning                                                                              |
| -------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------ |
| view → Desktop | `{ type: "dimos:chrome", pausable: true }`          | the view is framed: Desktop answers `dimos:chrome-ok` and the view shows its top bar |
| Desktop → view | `{ type: "dimos:visible", visible }`                | Details was shown or hidden: a hidden view polls nothing                             |
| view → Desktop | `{ type: "dimos:open-in-editor", file, line }`      | Open in editor: Desktop runs `POST /gateways/desktop/ui/editor/open` for it          |
| Desktop → view | `{ type: "dimos:open-in-editor-result", ok, text }` | what that ran (`opened: <command>`), or why it couldn't                              |
| view → Desktop | `{ type: "dimos:close" }`                           | its ✕, or Escape with nothing left to step back from: the modal closes               |

### The standalone app window

`/?view=standalone&app=<app>` is an app framed alone with Desktop's notifications over it (`dimos-desktop app
standalone`, [apps.md](apps.md#an-app-in-a-window-of-its-own-app-standalone)). The page says it's open with
`POST /gateways/desktop/ui/standalone/{id}` `{ app }` every `standalone.heartbeat-s` and `{ app, closed: true }` as it
goes (internal: not in /openapi.json); the light Desktop that command starts stops when none is left.

### Dimensional cloud: login and uploads

Uploads go to Dimensional cloud through dimos's own code (`dimos.cloud.data.CloudData().upload`, the same as
`dimos upload`), and the login is `dimos login`'s device flow: the user approves a code in any signed-in browser, and
the key is stored where dimos keeps it (keyring, else a 0600 file; `DIMOS_API_KEY` overrides). The dimos gateway runs
the uploads and keeps their queue, with a smoothed speed and time left.

| Method + path                   | Body / query                 | Response                                                                                     |
| ------------------------------- | ---------------------------- | -------------------------------------------------------------------------------------------- |
| `GET /dimos/cloud/account`      | `?fresh=1` (else cached 20s) | `{ loggedIn, email, scopes, source: "env"\|"stored"\|null, cloudUrl, error }`                |
| `POST /dimos/cloud/login`       |                              | `Login`, once the code is known (a pending login is returned as is)                          |
| `GET /dimos/cloud/login`        |                              | `Login`                                                                                      |
| `DELETE /dimos/cloud/login`     |                              | `Login` (the pending one is cancelled)                                                       |
| `POST /dimos/cloud/logout`      |                              | the account, logged out                                                                      |
| `GET /dimos/uploads`            |                              | `{ uploads: [Upload], waitingForLogin }`, oldest first                                       |
| `POST /dimos/uploads`           | `{ path, robotId?, kind? }`  | `Upload`. 400 for a path that isn't an existing `.mcap` / `.db`. Same path queued → that one |
| `DELETE /dimos/uploads`         |                              | `{ uploads, waitingForLogin }`: the finished ones (done, failed, cancelled) cleared          |
| `DELETE /dimos/uploads/:id`     |                              | `{ ok: true }`: a queued or running one is cancelled, a finished one removed                 |
| `POST /dimos/uploads/:id/retry` |                              | `Upload`, queued again at the back (409 while it is queued or running)                       |
| `GET /dimos/uploads/uploaded`   | `?path=` for one             | `{ byPath: { [path]: Uploaded } }`, or with `?path=` that `Uploaded` or `null`               |
| `GET /dimos/cloud/login/page`   | `?theme=light\|dark`         | an HTML page for an app's iframe that runs the login (below)                                 |

The queue is first in, first out, one at a time, and kept in `<DIMOS_HOME>/desktop/uploads.json`: one that was uploading
when the server stopped is queued again and dimos resumes it (the cloud keeps the parts it has). When an upload finds no
login it goes back to the front of the queue and `waitingForLogin` turns true; an approved login (or an account check
that finds one) starts the queue again. Errors are one readable sentence plus `errorCode`; the traceback is in `log`
(`<DIMOS_HOME>/desktop/logs/uploads.log`). Failed uploads also go into Desktop's error feed (docs/agent.md). Every done
upload is also remembered by path in `<DIMOS_HOME>/desktop/uploaded.json`, which clearing the list doesn't touch:
`GET /dimos/uploads/uploaded` says which recordings are in the cloud (for a link instead of an upload button), and
`changed` says the file is different now (its size or modification time). An app can run the login itself (`POST`, show
`code`, open `urlComplete` in a new tab, poll `GET`) or put `/dimos/cloud/login/page` in an iframe, which does that and
posts
`{ type: "dimos-cloud-login", state: "loggedIn" | "loggedOut" | "approved" | "denied" | "expired" | "failed" |
"cancelled", email }`
to its parent. The console's own page can't be framed (its sign-in sends `X-Frame-Options: DENY`), so the approval
always happens in a new tab or another device. `<ns>/dimos/events/upload` carries `{ type: "upload", upload }` on every
change (progress a few times a second), `{ type: "uploads", waitingForLogin }`, `{ type: "upload-removed", id }` and
`{ type: "cloud-login", login }`.

```ts
type Login = {
    state: "idle" | "starting" | "pending" | "approved" | "denied" | "expired" | "failed"
    url: string | null // where the user approves
    urlComplete: string | null // the same with the code filled in, when the cloud gives one
    code: string | null
    expiresAt: number | null // ms since the epoch
    email: string | null // once approved
    error: string | null
}
type Upload = {
    id: string // "u3"
    path: string
    name: string
    size: number
    robotId: string | null
    kind: string | null // null = dimos decides ("recording" for .mcap / memory2 .db)
    state: "queued" | "uploading" | "done" | "failed" | "cancelled"
    phase: "preparing" | "compress" | "hash" | "upload" | "finishing" | null
    bytesDone: number // of bytesTotal, for this phase: compress counts the file, hash and upload the compressed copy
    bytesTotal: number // 0: no byte count for this phase (an indeterminate bar; dimos before per-phase progress)
    rateBps: number | null // this phase's speed, smoothed (moving average over ~6 s)
    etaSeconds: number | null
    uploadId: string | null // the cloud's id
    skipped: boolean // the cloud already had this file
    notice: string | null // a quota warning
    error: string | null
    errorCode: "not_logged_in" | "network" | "quota" | "file_missing" | "failed" | null
    log: string | null
    createdAt: number // ms since the epoch
    startedAt: number | null
    finishedAt: number | null
    link: string | null // the Dimensional console's data page, once done
}
type Uploaded = {
    path: string
    uploadId: string
    size: number // the file's, when it was uploaded
    mtimeMs: number
    uploadedAt: number
    link: string | null
    changed: boolean // the file's size or modification time differs now
}
```

```ts
type RegistryRun = { run_id: string; pid: number; blueprint: string; started_at: string; log_dir: string }
type Launch = {
    blueprint: string
    phase: "starting" | "running" | "failed" | "stopped"
    startedAt: string
    pid: number
    output: string // tail of the launch's stdout/stderr
    runId: string | null
    logDir: string | null
    error: string | null
}
type LogRecord = { timestamp: string; level: string; logger: string; event: string; extra: object; raw: string }
```

## `/recordings/` — the shared recordings folder

Every recording apps make or open lives in one folder: `recordings.dir` in config.yaml (empty = `~/.dimos/recordings`,
under `DIMOS_HOME` when set), plus optional read-only `recordings.extra_dirs`. `.mcap` and `.db` (dimos memory2 SQLite)
files, up to one sub-folder deep. App servers get the folder as `DIMOS_APP`'s `recordingsDir`. An `id` is the path
relative to its folder (`live-viewer/drive.mcap`); extra folders' ids start `extra<N>/`.

| Method + path                 | Body               | Response                                                                       |
| ----------------------------- | ------------------ | ------------------------------------------------------------------------------ |
| `GET /recordings`             |                    | `{ dir, extraDirs: [string], recordings: [Recording] }`, newest first          |
| `GET /recordings/:id`         |                    | `RecordingMetadata` (reads the file's index; cached until the file changes)    |
| `GET /recordings/:id/file`    |                    | the file's bytes (`Content-Disposition: attachment`)                           |
| `POST /recordings/new`        | `{ name, format }` | `{ id, path }` — a free path in the main folder; the app writes the file there |
| `POST /recordings/:id/rename` | `{ name }`         | `Recording`                                                                    |
| `DELETE /recordings/:id`      |                    | `{ ok: true }` (main folder only; extra folders are read-only)                 |

```ts
type Recording = {
    id: string
    name: string
    format: "mcap" | "db"
    size: number
    modified: number
    path: string
    writable: boolean
}
type RecordingMetadata = Recording & {
    start: number | null // seconds since the epoch, over all streams
    end: number | null
    duration: number | null
    // .db: one per memory2 stream (type = dimos type, e.g. "sensor_msgs.PointCloud2"); .mcap: one per channel (type = schema name)
    streams: [{ name: string; type: string; count: number; start: number | null; end: number | null }]
}
```

`<ns>/desktop/events/recordings` (zenoh, [events.md](events.md)) carries `{ type: "recordings" }` after a rename or
delete.

## `/api/` — Desktop itself

| Method + path                         | Body / query                                                                               | Response                                                                                                                                                                                                                                                                                                          |
| ------------------------------------- | ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /api/info`                       |                                                                                            | `{ version, platform: { os, arch, steamDeck, steamOs, deckModel? }, config, dimos: <same as /dimos/info>, zenohGateway, service, agent }` (`platform`: [steam-deck.md](steam-deck.md))                                                                                                                            |
| `GET /api/steam-deck`                 |                                                                                            | `{ os, arch, steamDeck, steamOs, deckModel?, steam, steamRunning, launch: { browser, exe, startDir, launchOptions } \| null, url, users: [{ user, entry: missing\|present\|outdated }], needsShortcut, steamShortcut: missing\|outdated\|present\|unknown, gameId, runGameUrl }` ([steam-deck.md](steam-deck.md)) |
| `POST /api/steam-deck/shortcut`       |                                                                                            | `{ browser, users: [{ user, file, change: added\|updated\|unchanged, backup? }], steamRunning, message }`: "dimOS" in every Steam account's library (409 off a Deck/SteamOS, no Steam account, no browser)                                                                                                        |
| `POST /api/steam-deck/open`           |                                                                                            | `{ did: launched\|started\|restarted\|needs-restart, gameId, url, shortcut, message }`: opens "dimOS" through Steam (only when the user asked: it may restart Steam)                                                                                                                                              |
| `POST /api/open-in-editor`            | `{ file, line }` (file: relative to the dimos checkout, only inside it)                    | `{ ran, editor, file, line }`: opens it in the user's editor on this machine (UI settings `editor`, else $VISUAL / $EDITOR from the login shell, else `code`; vim, nano… in a terminal window)                                                                                                                    |
| `GET /api/config`                     |                                                                                            | the parsed `~/.dimos/config.yaml` (`desktop.password_hash` shows as `"(set)"`)                                                                                                                                                                                                                                    |
| `PUT /api/config`                     | partial config                                                                             | merged config (written back). `desktop.host` / the password change via `/api/auth/network`                                                                                                                                                                                                                        |
| `GET /api/dimos-dir`                  |                                                                                            | the checkout Desktop drives: `{ dir, default, isDefault, check, server, running, suggestions: [{ dir, branch, source, ok }] }` (worktrees, recent ones, the default)                                                                                                                                              |
| `GET /api/dimos-dir/check`            | `?dir=`                                                                                    | `{ dir, ok, errors, warnings, version, branch, commit, subject }`: is it a dimos checkout (package, pyproject, a dimos.yaml and robots.json that parse)                                                                                                                                                           |
| `PUT /api/dimos-dir`                  | `{ dir ("" = default), confirm?, stopRuns? }`                                              | as GET plus `{ changed, stopped, serverError }`: old server stopped, caches dropped, new server started, `dimos-dir` sent; 400 not a checkout; 409 while a run is live, unless `confirm`                                                                                                                          |
| `GET /api/apps`                       |                                                                                            | `{ apps: [App] }` (built-ins first)                                                                                                                                                                                                                                                                               |
| `GET /api/catalog`                    |                                                                                            | `{ entries: [CatalogEntry] }`; each has `installed` and `installs` (app names from its repo, copies included)                                                                                                                                                                                                     |
| `POST /api/apps`                      | `{ name?, url, ref? }`                                                                     | `{ job }` — install (a URL or a folder; `name` installs a separate copy); follow `<ns>/desktop/jobs/<job>` (zenoh)                                                                                                                                                                                                |
| `POST /api/apps/:pkg/update`          |                                                                                            | `{ job }`                                                                                                                                                                                                                                                                                                         |
| `GET /api/apps/updates`               | `?fresh=1`                                                                                 | `{ updates: [{ pkg, ref, commit, available, latest, latestCommit, behind, checkedAt, error }], available }`: which apps have an update (each fetched; reused 10 min)                                                                                                                                              |
| `POST /api/apps/update-all`           |                                                                                            | `{ jobs: [{ pkg, job }] }`: an update job per app with one, run one after another                                                                                                                                                                                                                                 |
| `GET /api/apps/nix-trust`             |                                                                                            | `{ trusted, user, caches, explanation, command }`: whether nix.conf trusts the dimOS and installed apps' binary caches, the untrusted urls, and the sudo command that trusts them (never run by Desktop)                                                                                                          |
| `GET /api/apps/:pkg/versions`         |                                                                                            | `{ current, tags: [string], betas: [string], branches: [string] }` (tags = stable, betas = suffixed tags, newest first)                                                                                                                                                                                           |
| `POST /api/apps/:pkg/checkout`        | `{ ref }`                                                                                  | `{ job }`                                                                                                                                                                                                                                                                                                         |
| `DELETE /api/apps/:pkg`               |                                                                                            | `{ ok: true }`                                                                                                                                                                                                                                                                                                    |
| `GET /api/apps/:pkg/icon`             |                                                                                            | the app's `icon.svg`                                                                                                                                                                                                                                                                                              |
| `GET /api/jobs`                       |                                                                                            | `{ jobs: [{ id, title, app, done, ok, … }] }`: running ones + finished in the last 30 min                                                                                                                                                                                                                         |
| `GET /api/jobs/:job/log`              | `?after=<n>`                                                                               | `{ lines, next, done, ok, error, failure, progress, title, kind, app }`: the job so far; live on zenoh at `<ns>/desktop/jobs/<job>` ([events.md](events.md), [app-store.md](app-store.md))                                                                                                                        |
| `GET /api/desktop/zenoh`              | `?app=<name>`                                                                              | `{ namespace, desktop, dimos, apps, zenohPrefix?, zenohGatewayUrl, client, up }`: where pages subscribe ([events.md](events.md))                                                                                                                                                                                  |
| `POST /desktop/frontend/:app/:topic…` | any body (JSON by default)                                                                 | `{ ok, key, bytes }`: publishes the body on `<ns>/apps/<app>/frontend/<topic…>`; 404 unknown app, 413 over 1 MiB                                                                                                                                                                                                  |
| `POST /api/errors`                    | `{ source, message, detail?, level? }`                                                     | `{ id, seq, count }`: into the error feed (docs/agent.md)                                                                                                                                                                                                                                                         |
| `GET /api/errors`                     | `?since=<seq>&unacknowledged=1&limit=50`                                                   | `{ errors: [ErrorEntry], latest, log }`                                                                                                                                                                                                                                                                           |
| `POST /api/errors/ack`                | `{ upTo? }`                                                                                | `{ acknowledged }`: marks them seen (all when no `upTo`)                                                                                                                                                                                                                                                          |
| `GET /api/install`                    |                                                                                            | `{ status: InstallStatus, needed: [string], logFile, offset, waitingForInput }`                                                                                                                                                                                                                                   |
| `POST /api/install/start`             | `{ nonInteractive?, dimcodeRef?, dimosRef? }`                                              | starts (or retries) the installer, every step straight through; 409 while it runs                                                                                                                                                                                                                                 |
| `POST /api/install/run`               | `{ all? }`                                                                                 | the installer page's Continue: runs the next step (or retries the failed one), then pauses (`state: "paused"`); `all` (Continue (All)) runs the rest without pausing, also mid-step                                                                                                                               |
| `POST /api/install/settings`          | `{ startOnBoot, networkAccess, password? }`                                                | Step 1: start on boot now; network access once the install finishes; with it, `password` (the installer page's, checked again) becomes the LAN password, kept only as a salted hash; answers the first-run question                                                                                               |
| `POST /api/install/sudo-check`        | `{ password }`                                                                             | `{ ok }`: the installer page only (shell tool's origin): `sudo -S -v` with it on stdin; never stored or logged                                                                                                                                                                                                    |
| `POST /api/install/sudo-answer`       | `{ password }`                                                                             | `{ typed }`: the installer page only: types it at the install terminal's sudo prompt, only while it asks for a password                                                                                                                                                                                           |
| `POST /api/install/fix`               |                                                                                            | Fix it with the agent: `status.agentFix` follows its shell tool calls on `install`; `shell_resolve` retry there retries the step                                                                                                                                                                                  |
| `POST /api/desktop/shell`             | `{ title, message?, app?, commands: [{ run, note, needsStdout?, cwd?, env? }], timeout? }` | `{ id, status, session }`: commands an app wants run, shown over it; nothing runs until the user presses Run ([shell.md](shell.md))                                                                                                                                                                               |
| `GET /api/desktop/shell/:id`          | `?wait=<s>`                                                                                | the session and each command's `exitCode`, `output`, `stdout` / `stderr` (with `needsStdout`); `wait` holds it until it finishes                                                                                                                                                                                  |
| `GET /api/desktop/shell`              |                                                                                            | `{ sessions }`: every session kept (`install` is the installer's terminal)                                                                                                                                                                                                                                        |
| `GET /api/desktop/shell/:id/output`   | `?after=<offset>&plain=1`                                                                  | `{ text, offset, status, running, busy, prompt }`: its terminal since `after`                                                                                                                                                                                                                                     |
| `POST /api/desktop/shell/:id/input`   | `{ text, enter?: true }`                                                                   | typed into its shell (409 at a password prompt or with no shell)                                                                                                                                                                                                                                                  |
| `POST /api/desktop/shell/:id/:action` | `{ by?, key? }`                                                                            | `run`, `retry`, `skip`, `done`, `cancel`, `dismiss`                                                                                                                                                                                                                                                               |
| `GET /api/auth`                       |                                                                                            | `{ local, passwordSet, networkAccess, authenticated, port, urls }`                                                                                                                                                                                                                                                |
| `POST /api/auth/login`                | `{ password }` or `{ token }`                                                              | sets the session cookie; 401 for a wrong one                                                                                                                                                                                                                                                                      |
| `POST /api/auth/logout`               |                                                                                            | clears it                                                                                                                                                                                                                                                                                                         |
| `GET /api/auth/local-token`           |                                                                                            | `{ token }`, only to this machine (see Network access)                                                                                                                                                                                                                                                            |
| `POST /api/auth/network`              | `{ enabled, password?, current? }`                                                         | network access on (needs a password) or off; Desktop restarts to listen anew. This machine or a logged-in session; a new password from another machine needs `current`                                                                                                                                            |
| `POST /api/auth/password`             | `{ password, current? }`                                                                   | changes the LAN password (8+ characters; `current` needed from another machine); signs other sessions out, the caller gets the new cookie                                                                                                                                                                         |
| `GET /api/zenoh-gateway`              |                                                                                            | `{ enabled, up, url, version, external, external_url, external_error, encoder, error, relay_only, ice }` — `url` is the gateway base; apps POST `<url>/offer`; `external`: Desktop proxies to a zenoh-gateway on `zenoh_gateway.external_port`                                                                    |
| `GET /api/agent`                      |                                                                                            | `{ installed, running, ready, foreign, ... }` (`foreign`: another dimcode's gateway on the socket)                                                                                                                                                                                                                |
| `POST /api/agent/restart`             |                                                                                            | `dimcode stop` (the terminal's too); the next `/agent/` request starts it                                                                                                                                                                                                                                         |
| `POST /api/agent/start`               |                                                                                            | start it now (as the first `/agent/` request would); 503 + `error` when it can't                                                                                                                                                                                                                                  |
| `POST /api/agent/replace`             |                                                                                            | stop the other dimcode's gateway on the socket, start Desktop's (the warning's Replace it)                                                                                                                                                                                                                        |
| `POST /api/agent/separate-socket`     |                                                                                            | `agent.socket` = `<DIMOS_HOME>/dimcode.sock` and start Desktop's agent there                                                                                                                                                                                                                                      |
| `/agent/*` (HTTP, websocket)          |                                                                                            | the agent's own page, proxied to its socket (started on demand)                                                                                                                                                                                                                                                   |

```ts
type App = {
    id: string // "<pkg>/<app>", e.g. "dim-go2-dash/go2_dash"; built-ins: "builtin/<name>"
    pkg: string
    name: string
    title: string
    icon: string // URL
    url: string // frontend URL (iframe src)
    builtin: boolean
    ref: string | null // git ref checked out
    compat: { ok: boolean; problems: string[]; warnings: string[] }
    backend: { running: boolean; restarts: number; log: string } | null
}
type CatalogEntry = { name: string; title: string; description: string; url: string; icon: string; installed: boolean }
```

## The shell: notifications, settings, HUD, search, events

| Method + path                                                                         | Body / query                                                                        | Response                                                                                                                                                                                                                                                                                            |
| ------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `POST /api/notifications`                                                             | `{ title, body?, icon?, app?, kind?, sound?, actions?, details?, robot?, modals? }` | `{ id, notification }`: a banner with a sound on every page, the panel, the badge, and a system notification from the shell page while it's in the background (the browser's Notification API, when turned on in Settings; secure origins only)                                                     |
| `GET /api/notifications`                                                              |                                                                                     | `{ notifications: [Notification] (newest first, dismissed ones too), unread }`                                                                                                                                                                                                                      |
| `POST /api/notifications/:id/dismiss`                                                 |                                                                                     | `{ ok }`                                                                                                                                                                                                                                                                                            |
| `POST /api/notifications/clear`                                                       |                                                                                     | `{ ok }`: dismisses all                                                                                                                                                                                                                                                                             |
| `POST /api/notifications/read`                                                        |                                                                                     | `{ ok }`: marks all read (opening the panel does)                                                                                                                                                                                                                                                   |
| `GET /api/ui-settings`                                                                |                                                                                     | `UiSettings`                                                                                                                                                                                                                                                                                        |
| `PUT /api/ui-settings`                                                                | a partial `UiSettings`, or the whole one sent back                                  | `UiSettings` (saved in config.yaml `ui:` and `zenoh_gateway.hardware_encode`)                                                                                                                                                                                                                         |
| `GET /api/hud`                                                                        |                                                                                     | `{ uptime, desktopUptime, robot: {name, ip} \| null, link, cpu, blueprint: {name, phase} \| null, dimosVersion }` (unknown = null)                                                                                                                                                                  |
| `GET /api/search`                                                                     | `?q=&kinds=app,blueprint,module,topic,recording,setting,desktop&limit=8`            | `{ query, term, verb, results: [{ kind, title, meta, id }] }`: word-start matching; `open x` / `run x`                                                                                                                                                                                              |
| `GET /api/topics/rates`                                                               |                                                                                     | `{ up, error?, topics: [{ topic, type, hz, bps, history }] }` busiest first (counted while asked, for 20 s)                                                                                                                                                                                         |
| `POST /api/close-app`                                                                 | `{ app? }`                                                                          | minimizes the app in every window showing it (default: the one on screen)                                                                                                                                                                                                                           |
| `POST /api/desktop/viewer`                                                            | `{ url, title?, window? }`                                                          | shows `url` (a path on this Desktop, e.g. the agent's `/agent/view/3d?urdf=…`) as a full-screen layer with ✕ over the window used last; 400 for other URLs, 409 with no window                                                                                                                      |
| `GET /dimos/blueprints/:name/config`                                                  |                                                                                     | `{ name, modules: [{ module, class, args: [{ name, type, default, description, required, base, choices?, value? }], error? }] }`                                                                                                                                                                    |
| `GET /shell/theme.css`, `/shell/sfx.js`, `/shell/icons.js`, `/shell/icons/<name>.svg` |                                                                                     | the shell's shared assets (the portal mockup's components, which `@import` /theme.css, sounds and icons), for Desktop and the portal page                                                                                                                                                           |
| `GET /theme.css`                                                                      |                                                                                     | Desktop's theme: every skin's tokens (Portal as `:root`, each skin as `html[data-skin="<id>"]`, the corners as `html[data-corners]`); the shell, the built-ins and every app style themselves with it (an app at `/apps/<name>/` links `../../theme.css`; dim-app's theme.js does). No login needed |

### Notification actions and modals

`actions` are `[label, action]` buttons. An action is one of:

| Action                              | What the button does                                                                                                                                       |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `<app>`, `open:<app>[/<path>]`      | opens the app (a built-in's path is its section: `open:settings/settings-updates`)                                                                         |
| `open:appstore/app=<pkg>&log=<job>` | the App Store on that app, with that job's log sheet open (while Desktop keeps the job: 30 minutes)                                                        |
| `open:launcher/?blueprint=<bp>`     | the Launcher with that blueprint selected                                                                                                                  |
| `chat`, `events`                    | the agent's chat; nothing (the panel)                                                                                                                      |
| `toast:<text>`                      | a toast                                                                                                                                                    |
| `run:<blueprint>`, `stop`           | launches a blueprint; stops the running one                                                                                                                |
| `logs:<blueprint>[/<runId>]`        | that run's Details on its Logs                                                                                                                             |
| `post:<path>[ <json>]`              | POSTs to a Desktop or app endpoint; a JSON body may follow one space (`post:/api/apps/x/update {"force":true}`). Its answer's `message`/`error` is toasted |
| `modal:<key>` (or `modal`)          | opens `modals[key]` (`modal`: the first one)                                                                                                               |
| `dismiss`                           | dismisses this notification (a modal's Cancel)                                                                                                             |
| `close`                             | closes the modal (in a modal's buttons)                                                                                                                    |

`modals` is `{ <key>: { title?, body, pre?, copy?, actions? } }`: what a `modal:<key>` button opens, kept with the
notification, so it opens later from the panel too. `title` defaults to the notification's. `body` is markdown
(paragraphs, `**bold**`, `*italic*`, `` `code` ``, fences, `-`/`1.` lists, `#` headings, http(s) links; HTML is
escaped). `pre` is preformatted text under it (a log, a traceback; its last 20000 characters are kept, and it opens
scrolled to its end). `copy: true` adds a Copy button for the body and the pre (a string: copies that). `actions` are
the modal's own buttons, the same kinds; the first is styled as the decision, and any button but `modal:<key>` closes
the modal after it runs (no `actions`: a Close button). A `modal:<key>` that names no modal is a 400, as is a `post:`
body that isn't JSON; at most 8 modals.

```json
{
    "title": "Switching Rerun to v0.1.7 needs your OK",
    "body": "dim-rerun's pages connect outside Desktop.",
    "kind": "warn",
    "actions": [["Review & allow", "modal:review"]],
    "modals": {
        "review": {
            "title": "Let Rerun connect outside Desktop?",
            "body": "**It asks to reach:**\n- http://*:* (any machine, any port)",
            "actions": [
                ["Allow and switch to v0.1.7", "post:/api/apps/dim-rerun/checkout {\"ref\":\"v0.1.7\",\"force\":true}"],
                ["Cancel", "dismiss"]
            ]
        }
    }
}
```

Desktop's own notifications use them: an App Store job that needs the user's OK (its pages connect outside Desktop, or
it needs what this Desktop doesn't have) offers **Review & allow** (or **Review**): a modal with exactly what it asks
for and the same decision the App Store's buttons make (the request again with `force`). A failed install, update or
version switch offers **Show details** (the error and the job log's tail, Copy, Retry, Open in App Store) and **Retry**,
and **Open <app>** only while the app is still installed and built; a finished one, **Open <app>**. A blueprint that
failed offers **Show details** (the error, the exception it ended with and its last output, with Open logs, Open in
Launcher, Run again) and **Open in Launcher**; one that stopped, **Run again**. A rolled-back Desktop update posts one
with its reason and the watchdog's lines.

```ts
type Notification = {
    id: number
    title: string
    body: string
    icon: string | null // an icon id from /shell/icons.js, an installed app's name, or a URL
    app: string | null // who sent it: "desktop", "agent", an app's name
    kind: "ok" | "warn" | "agent" | "events" | null // agent/events also list under "Agent events"
    sound: "default" | "urgent" | "battery" | null
    actions: [label: string, action: string][] // an app name, open:<app>/<path>, chat, events, toast:<text>, run:<blueprint>, stop, logs:<blueprint>[/<runId>], post:<path>
    details: string | null
    robot: string | null
    time: number // ms since the epoch
    unread: boolean
    dismissed: boolean
}
type UiSettings = {
    theme: "portal" | "green" | "retro" | "research" | "vibeslop-light" | "vibeslop" | "hackerman"
    portalPosition: "center" | "float-left" | "float-right" // a portal from before the split; the chat box is at the left
    corners: "theme" | "sharp" | "rounded" // "theme": each theme's own (Portal square, Research rounded)
    pinned: string[] // the dock, in order (the default set until changed)
    sounds: { on: boolean; pack: string; volume: number }
    crt: boolean
    autoRecord: boolean
    editor: string // the command POST /api/open-in-editor runs; "": $VISUAL, then $EDITOR (login shell), else code
    hardwareEncode: boolean
    networkAccess: boolean // read-only here: POST /api/auth/network
    passwordSet: boolean // read-only
}
```

### Desktop events (zenoh `<ns>/desktop/events/<type>`)

Published on zenoh, one JSON object `{type, …}` per sample; pages hear them through zenoh-gateway
([events.md](events.md)). The dimos gateway publishes its own events on `<ns>/dimos/events/<type>`. (`GET /api/events`,
the old SSE stream, is deprecated and internal, kept one release.)

| `type`             | fields                                                     | when                                                                                                                           |
| ------------------ | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `apps`             |                                                            | an app was installed, removed, updated, started or stopped                                                                     |
| `endpoints`        | `app, added, removed` (`{method, path, description}` each) | an app's agent endpoints changed (install, update, uninstall, a rebuilt agent.json)                                            |
| `blueprints`       | `added, removed` (names)                                   | the blueprint list changed (the dimos gateway's `blueprints` event, relayed)                                                   |
| `runs`             |                                                            | a blueprint run started or stopped (from Desktop or a terminal)                                                                |
| `notification`     | `notification`                                             | a new notification                                                                                                             |
| `notifications`    |                                                            | some were dismissed or read                                                                                                    |
| `ui-settings`      | `settings`                                                 | a setting changed (any page, the agent)                                                                                        |
| `dimos`            | `event`                                                    | the dimos gateway's `{type:"launch",launch}`, `{type:"log",record}`, `{type:"upload",upload}`                                  |
| `job`              | `job, title`                                               | a background job started                                                                                                       |
| `install`          | `status`                                                   | the installer's progress                                                                                                       |
| `recordings`       |                                                            | a recording was renamed or deleted                                                                                             |
| `error`            | `error`                                                    | a new entry in the error feed                                                                                                  |
| `launcher`         | `state`                                                    | the Launcher's state changed (any page, the agent)                                                                             |
| `launcher-catalog` |                                                            | the Launcher's catalog was rescanned                                                                                           |
| `dimos-dir`        | `dir, previous`                                            | Desktop switched dimos checkouts: re-read what came from it (pages get a `resync`)                                             |
| `endpoint-stats`   | `at, totals, changed`                                      | per-endpoint call counts changed (at most once a second; see Call counts)                                                      |

## Desktop describing itself: OpenAPI, dimos.yaml, the endpoint registry, call counts

For tools that explore a running system (the Endpoint Explorer app) and for the agent. Same origin, so an app's page
calls them directly (`fetch("/api/endpoints/stats")`). Source: `src/server/openapi.rs`, `src/server/call_stats.rs`.

| Method + path                 | Query   | Response                                                                                        |
| ----------------------------- | ------- | ----------------------------------------------------------------------------------------------- |
| `GET /api/desktop/openapi`    |         | an OpenAPI 3.1 document of every route Desktop serves (its own and the dimos gateway's)         |
| `GET /api/desktop/dimos.yaml` |         | `text/yaml`: Desktop's dimos.yaml plus `title` and `agent: { description, endpoints }`          |
| `GET /api/endpoints`          | `?app=` | `{ apps: [RegistryApp] }`: the registry `search_endpoints` searches                             |
| `GET /api/endpoints/stats`    |         | `EndpointStats`: calls per endpoint, by family                                                  |
| `GET /agent/api/openapi`      |         | the agent gateway's own routes, as OpenAPI 3.1 (served by dimcode, through the `/agent/` proxy) |

**The OpenAPI document** lists every route registered in Desktop's router and the dimos gateway's (a test parses both
routers' source and fails on a route the document lacks). Each operation has `operationId`, `summary`, `description`,
`tags` (one group), `parameters` (path and, for GET/DELETE, query), `requestBody` (POST/PUT JSON fields), `responses`
(the shape, in words) and:

- `x-family`: `"dimos"` for `/dimos/...` (the dimos gateway), else `"desktop"`
- `x-agent: true`: one of `endpoints::builtins()`, which the agent finds through `search_endpoints`
- `x-mcp-tool`: the MCP tool(s) that do the same, e.g. `notify` for `POST /api/notifications`

The group docs are in `tags[].description` (markdown, with `x-family`): how the dimos gateway is started and proxied,
blueprint enumeration and list changes, runs and launch phases, logs, config introspection, cloud uploads (all the dimos
gateway's, which Desktop proxies); apps (install, update, serving), notifications, UI settings, the HUD, topics and
zenoh-gateway, search, the event stream, the agent and MCP, auth, recordings, windows, errors, the installer, the
Launcher and these endpoints. Desktop's own websocket (a shell session's terminal) and the deprecated SSE `/api/events`
are internal to its UI and CLI: not in the document, and apps must not rely on them.

```ts
type RegistryApp = {
    app: string // "desktop", "launcher", or an installed app's name
    title: string
    description: string
    // where the endpoints came from: Desktop's built-ins, or the app's dimos.yaml `agent:` merged with the file it
    // serves (the served file wins: "agent.json", else "openapi.json"; just "dimos.yaml" when it serves neither)
    source: "builtin" | "dimos.yaml" | "agent.json" | "openapi.json"
    manifestUrl?: string // "/api/desktop/dimos.yaml" for Desktop, "/apps/<name>/agent.json" for a served one
    endpoints: {
        method: string
        path: string // absolute for Desktop's ("/dimos/runs"), relative for an app's ("api/open")
        description: string
        params: { [name: string]: { type?: string; description?: string; required: boolean } }
        role?: "view" | "context"
    }[]
}
type EndpointStats = {
    since: number // ms since the epoch counting started (Desktop's start)
    now: number
    totals: { calls: number; errors: number; perSec: number }
    families: { [family: string]: EndpointCount[] } // "desktop", "dimos", "agent", "app:<name>"
}
type EndpointCount = {
    method: string
    path: string // the path template ("/dimos/blueprints/{name}", "api/open"), "(frontend)", or the raw path
    calls: number
    errors: number // responses with status >= 400
    lastCall: number | null // ms since the epoch
    meanMs: number // to the response's headers (a stream counts until it starts)
    perSec: number // calls in the last 10 s / 10
    matched: boolean // false: no registry path fits, so `path` is the raw path
}
```

### Call counts

A middleware around the whole router (outside auth, so refused requests count too) counts every request Desktop serves
or proxies, once its response headers are ready:

| Request                                                          | Family       | `path`                                                                                                                                                             |
| ---------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `/api/…`, `/mcp`, `/recordings…`, `/healthz`, `/zenoh-gateway/…` | `desktop`    | the OpenAPI path template it fits                                                                                                                                  |
| anything else (the embedded UI's files)                          | `desktop`    | `(frontend)`                                                                                                                                                       |
| `/dimos/…`                                                       | `dimos`      | the dimos gateway route it fits (`/dimos/blueprints/{name}/config`)                                                                                                |
| `/agent/…`                                                       | `agent`      | the gateway route it fits, from its `GET /api/openapi` (`/api/settings`)                                                                                           |
| `/apps/<name>/…`                                                 | `app:<name>` | the app's endpoint it fits (`api/open`); `agent.json` / `openapi.json` (its manifest, which Desktop reads for the registry); another non-`api/` path: `(frontend)` |

- A template's `{param}` takes one path segment; only when nothing fits that way may it take several (a recording id
  like `live/a.mcap`). The template with the most literal segments wins.
- A request no template fits is kept under its raw path with `matched: false`; past 100 such paths in a family the rest
  go under `(other)`. When an app's manifest (or the agent's routes) later gains a fitting endpoint, those counts move
  to it.
- App templates come from the registry, re-read at startup, every 60 s and after an app changes. The agent's are fetched
  from its socket after the first `/agent/` request, then at most once a minute (never starting the agent).
- `GET /api/endpoints/stats` isn't counted (polling the stats would count itself).
- The agent's `call_endpoint` and app servers' calls back into Desktop go through Desktop's HTTP server, so they count
  like a page's.

Live: `<ns>/desktop/events/endpoint-stats` carries
`{ type: "endpoint-stats", at, totals, changed: [{ family, method, path, calls, errors,
perSec, lastCall }] }` at most
once a second, only when something changed: an endpoint was called, or its `perSec` decayed since the last event (so a
quiet endpoint's rate reaches 0). Keep the full table from `GET /api/endpoints/stats` and patch it with `changed`.

## Network access

Desktop listens on `127.0.0.1` unless network access is on (`desktop.host: 0.0.0.0`), which needs a password (setup asks
for one, or generates and prints one when an agent runs it; `dimos-desktop password` or Settings → Network access
changes it). Without a password Desktop refuses to listen beyond localhost: its UI includes a terminal.

- This machine (a loopback peer) never needs the password.
- Any other peer gets 401 for everything but `/healthz`, `/api/auth*` and the shell's own files until it logs in
  (`POST /api/auth/login` → an HttpOnly, SameSite=Strict session cookie, which websockets and app iframes send too). The
  page remembers a typed password in localStorage and logs in with it next time.
- A page this machine opened through one of its own LAN addresses (so it looks remote) asks
  `http://127.0.0.1:<port>/api/auth/local-token` for a token and logs in with it, so the user here never types the
  password. That endpoint answers only loopback callers, and with CORS only for an `Origin` that is this Desktop's port
  on an address this machine owns; elsewhere the request just fails and the login form shows.
- The password is stored salted and stretched (`desktop.password_hash`); the session token derives from it, so changing
  the password signs everyone out.
- Anything that forwards traffic into localhost (an SSH tunnel, a `tailscale serve`, a local proxy) looks local and
  skips the password.

## App plumbing

- `/apps/<name>/…` — a static app's files, or forwarded to its `dimos-app-server` socket with `/apps/<name>` removed
  (websockets too).
- `/zenoh-gateway/…` — the embedded zenoh-gateway; app pages reach it at `../../zenoh-gateway` (relative to
  `/apps/<name>/`). When a compatible zenoh-gateway (`>=0.5 <0.6`) already listens on `zenoh_gateway.external_port`
  (default 7448; 0 = never), Desktop proxies to it instead and starts the embedded one again when it goes away; the URL
  apps use doesn't change. `GET /zenoh-gateway/zenoh-gateway/ice` gets Cloudflare TURN credentials
  (`zenoh_gateway.cloudflare_turn`) and `iceTransportPolicy: "relay"` (`zenoh_gateway.relay_only`) added.
