# Events: backend → frontend over zenoh

Desktop's public API is **HTTP plus zenoh-gateway**. Everything a page (the shell, a view, an app's frontend, an iframe)
_asks_ for goes over plain HTTP; everything a backend _pushes_ to a page goes over zenoh and reaches the browser through
Desktop's zenoh-gateway (WebRTC). Server-Sent Events and websockets are not part of the public API.

## The rule

- **Backend → frontend is always zenoh**, delivered to browsers by zenoh-gateway. Each frontend (a page, or an iframe
  that is its own page) keeps **one** zenoh-gateway connection and subscribes to what it needs on it; zenoh-gateway
  shares that connection's bandwidth between the subscriptions (events are small and reliable, so they always get
  through ahead of bulk streams).
- **Frontend → backend is plain HTTP** (`POST`, `PUT`, `DELETE`, …), to Desktop or to the app's own server.
- **State is HTTP, changes are zenoh** ("snapshot + live", below): a page `GET`s the current state, then applies the
  events; after its zenoh-gateway connection comes back it `GET`s again.
- **Any backend can push to its frontend with one HTTP call**: `POST /desktop/frontend/<app>/<topic…>` (the relay,
  below). A backend that speaks zenoh itself (Rust, C++, Python with zenoh) may publish on the key directly instead; the
  key layout here is public and stable.

Exceptions, for now: a shell session's terminal (`/api/desktop/shell/<id>/terminal`, the installer's and the ones apps
ask for, [shell.md](shell.md)) and the agent's chat stream (dimcode's own page, `/agent/…`) keep their websockets.

## The namespace

Every key Desktop uses starts with its namespace, `<ns>`, so several Desktops (other machines on the LAN, or two
versions on one machine) can share a zenoh network without hearing each other.

```yaml
# ~/.dimos/config.yaml
desktop:
    namespace: "" # empty = the default below; or e.g. "lab/robot-desk"
```

The default is **`dimos-desktop/<host>-<port>`**: `<host>` is this machine's hostname, lowercased, with anything but
`a-z 0-9 -` turned into `-` (`Jeffs-MacBook.local` → `jeffs-macbook-local`), and `<port>` is `desktop.port`. Why: a
fixed default (e.g. `dimos/desktop`) would make every Desktop on a LAN deliver its window commands and notifications to
every other Desktop's pages (zenoh peers find each other by multicast); the hostname separates machines and the port
separates two Desktops on one machine, while staying the same across restarts so native publishers can be configured
once. A configured `namespace` must be a valid zenoh key expression with no wildcards (`*`, `$*`), no `?`, `#`, and no
empty chunks; Desktop refuses to start with an invalid one.

Nobody hardcodes `<ns>`: backends read it from `DIMOS_APP`, pages from `GET /api/desktop/zenoh`.

## Keys

| Key                                 | Who publishes                         | Payload                                                        |
| ----------------------------------- | ------------------------------------- | -------------------------------------------------------------- |
| `<ns>/desktop/events/<type>`        | Desktop                               | a Desktop event, `{type, …}` (table below)                     |
| `<ns>/desktop/jobs/<jobId>`         | Desktop                               | a job's output: `{type:"line", n, line}` … `{type:"done", …}`  |
| `<ns>/desktop/windows/<windowId>`   | Desktop                               | a command for one shell window: open, close (minimize), viewer |
| `<ns>/dimos/events/<type>`          | Desktop (for the dimos gateway)       | a dimos gateway event, `{type, …}`                             |
| `<ns>/apps/<app>/frontend/<topic…>` | the app's backend, or Desktop's relay | whatever the app defines (JSON by default)                     |
| `<ns>/apps/<app>/<anything else>`   | the app                               | reserved for the app's own use                                 |

`<app>` is the app's **install name** (`DIMOS_APP.name`), not its repo name, so two installs of one repo (`--name a`,
`--name b`, e.g. two versions) never collide. `<topic…>` is one or more key chunks the app picks (`status`, `map/cloud`,
…).

Every event payload repeats its type inside (`{"type": "apps"}` on `<ns>/desktop/events/apps`), so a subscriber on
`<ns>/desktop/events/**` can dispatch on the payload alone.

### Desktop events: `<ns>/desktop/events/<type>`

| `<type>`           | Payload                                                                 | Then                             |
| ------------------ | ----------------------------------------------------------------------- | -------------------------------- |
| `apps`             | `{type}`: an app was installed, removed, updated, started or stopped    | `GET /api/apps`                  |
| `job`              | `{type, job, title, kind, app}`: a background job started               | follow `<ns>/desktop/jobs/<job>` |
| `notification`     | `{type, notification}`: a new notification (the whole object)           | —                                |
| `notifications`    | `{type}`: some were read, dismissed or cleared                          | `GET /api/notifications`         |
| `ui-settings`      | `{type, settings}`: the whole `GET /api/ui-settings` object             | —                                |
| `install`          | `{type, status}`: installer progress (the `GET /api/install` object)    | —                                |
| `shell`            | `{type, session}`: a shell session changed (no command output)          | `GET /api/desktop/shell/<id>`    |
| `recordings`       | `{type}`: a recording was renamed, deleted or added                     | `GET /recordings`                |
| `runs`             | `{type}`: a blueprint run started or stopped                            | `GET /dimos/runs`                |
| `blueprints`       | `{type, added:[names], removed:[names]}` (the dimos gateway's, relayed) | `GET /dimos/blueprints`          |
| `endpoints`        | `{type, app, added:[{method,path,description}], removed:[…]}`           | `GET /api/endpoints`             |
| `endpoint-stats`   | `{type, at, totals, changed:[…]}`, at most once a second                | `GET /api/endpoints/stats`       |
| `error`            | `{type, error}`: a new error-feed entry                                 | `GET /api/errors`                |
| `launcher`         | `{type, state}`: the Launcher's shared state                            | —                                |
| `launcher-catalog` | `{type}`: the Launcher's catalog scan finished                          | `GET /api/launcher/catalog`      |
| `dimos-dir`        | `{type, dir, previous}`: Desktop switched dimos checkouts               | re-GET everything                |

New types can appear; a subscriber ignores types it doesn't know.

### Jobs: `<ns>/desktop/jobs/<jobId>`

A job (install, update, checkout; `POST /api/apps` and friends answer `{job}`) publishes each output line as
`{type:"line", n, line}` (`n` counts from 0), `{type:"progress", progress}` as it moves (at most 5 a second; not
numbered, the newest wins: [app-store.md](app-store.md)) and finally `{type:"done", ok, error, failure, lines}` (`lines`
= how many there were). The snapshot is `GET /api/jobs/<jobId>/log?after=<n>` →
`{lines:[…], next, done, ok, error,
failure, progress}` (the lines from `after` on, default 0; `next` = the `n` the next
line will have). A page subscribes first, then fetches the log, then applies live lines whose `n` ≥ the snapshot's
`next` (and re-fetches from its last `n` when one is skipped). Finished jobs stay readable for 30 minutes
(`GET /api/jobs` lists them).

### Windows: `<ns>/desktop/windows/<windowId>`

Each shell window (browser tab) has an id (kept in `sessionStorage`, so a reload keeps it) and registers over HTTP:

- `POST /api/windows/<windowId>` `{focused, visible, app, path, title, open}`: its state, sent on every change and at
  least every 10 s as a heartbeat. A window not heard from for 30 s is dropped.
- `POST /api/windows/<windowId>/active`: the user clicked or typed in it (agents' `open-app` goes to the window used
  last).
- `POST /api/windows/<windowId>/close`: it's going away (`navigator.sendBeacon` on `pagehide`).

Commands for it arrive on its key: `{type:"open-app", app, path, focus}`, `{type:"close-app", app}` (minimize `app`, or
whatever is shown when `app` is null), `{type:"viewer", url, title}`, `{type:"capture-app", app, id}` (the agent's
`screenshot`: draw the app on screen and post the JPEG, or `{error}` as JSON, to
`POST /api/windows/<windowId>/capture/<id>`). They come from `POST /api/open-app`, `POST /api/close-app`,
`POST /api/desktop/viewer` and the MCP's `screenshot` (and the agent's tools that call them). `GET /api/windows` lists
the windows.

### The dimos gateway: `<ns>/dimos/events/<type>`

`launch` (`{type, launch}` on a phase change), `log` (`{type, runId, record}`, warning and above), `upload`
(`{type, upload}`), `uploads` (`{type, waitingForLogin, cleared?}`), `upload-removed` (`{type, id}`), `cloud-login`
(`{type, login}`), `blueprints` (`{type, added, removed}`: the blueprint list changed) and `discovery`
(`{type, status}`: the discovery scan's progress). The dimos gateway (dimos/gateway/, started with
`DIMOS_ZENOH_NAMESPACE=<ns>` and `ZENOH_CONNECT`) publishes them itself. Desktop hears them on the same keys through its
own zenoh session (zenoh-gateway's: none are heard while it's off) to post launch notifications, put failed uploads in
the error feed and ask for the Launcher's catalog again when the blueprints change.

## The relay: `POST /desktop/frontend/<app>/<topic…>`

```sh
curl -X POST http://127.0.0.1:7341/desktop/frontend/dim-controller/status -H 'content-type: application/json' \
     -d '{"battery": 0.82}'
```

publishes the body, unchanged, on `<ns>/apps/dim-controller/frontend/status`, and answers
`{"ok": true, "key": "<ns>/apps/dim-controller/frontend/status", "bytes": 16}`.

- The body is the payload as is: JSON, text or bytes. Its `content-type` becomes the zenoh sample's encoding
  (`application/json` when none is given), so a native subscriber can tell.
- `<app>` must be an installed app (404 otherwise); `<topic…>` is one or more chunks of letters, digits, `-`, `_`, `.`
  (400 for anything else, including wildcards and empty chunks).
- Bodies over **1 MiB** are refused (413). Events should stay small (≤ 64 KiB); anything bigger is fetched over HTTP by
  an id the event carries.
- 503 when Desktop's zenoh session isn't open (zenoh-gateway disabled or still starting).
- From an app's own server: `${DIMOS_APP.desktopUrl}/desktop/frontend/${DIMOS_APP.name}/<topic>`. Agents use the same
  call (it's in `GET /api/desktop/openapi` and the MCP endpoint list).

Desktop's own events don't go through the relay; nothing outside Desktop may publish under `<ns>/desktop/` or
`<ns>/dimos/`.

## Finding the namespace

**Backends**: `DIMOS_APP` (docs/apps.md) has `zenohNamespace` (`<ns>`) and `zenohPrefix` (`<ns>/apps/<name>`).

**Pages**: `GET /api/desktop/zenoh` (from an app: `../../api/desktop/zenoh`), optionally `?app=<name>`:

```json
{
    "namespace": "dimos-desktop/jeffs-mac-7341",
    "desktop": "dimos-desktop/jeffs-mac-7341/desktop",
    "dimos": "dimos-desktop/jeffs-mac-7341/dimos",
    "apps": "dimos-desktop/jeffs-mac-7341/apps",
    "zenohPrefix": "dimos-desktop/jeffs-mac-7341/apps/dim-controller",
    "zenohGatewayUrl": "/zenoh-gateway",
    "client": "https://esm.sh/gh/jeff-hykin/zenoh-gateway@dc00dd7/client/zenoh_gateway.ts",
    "up": true
}
```

`zenohPrefix` is there only with `?app=`. `client` is the zenoh-gateway client at the commit Desktop's gateway is built
from.

```js
const info = await (await fetch(new URL("../../api/desktop/zenoh?app=dim-controller", location.href))).json()
const { connect } = await import(info.client)
const zenoh = await connect(new URL("../../zenoh-gateway", location.href).href)
zenoh.subscribe(`${info.zenohPrefix}/frontend/**`, { delivery: "reliable" }, (message) => {
    const event = JSON.parse(new TextDecoder().decode(message.bytes))
})
```

## Payloads

- **JSON, UTF-8, by default**: one object per sample. Desktop's own events are always JSON objects with a `type`.
- **Bytes are allowed** on app keys (the relay passes them through; zenoh carries them as is). Say which in the app's
  docs, and set the content-type when relaying.
- Subscribe to events with `delivery: "reliable"` (ordered, nothing dropped). `"latest"` keeps only the newest sample
  per key, which is right for state that replaces itself (a robot pose) and wrong for events.

## Snapshot + live

1. Subscribe (on the page's one zenoh-gateway connection).
2. `GET` the state over HTTP.
3. Apply events as they come; an event either carries the change (small payloads: a notification, the settings) or just
   says what changed (`{type:"apps"}`, or `{key, version}` for an app's own state) and the page re-`GET`s.
4. When the connection state goes back to `connected` after `lost` (`zenoh.onState`), `GET` everything again: events
   published while it was down are gone.

Big payloads (point clouds, files, logs) never ride in an event: the event carries an id or a version, and the page
fetches the bytes over HTTP.

## Security

Auth is **off** for zenoh keys for now: any page that can reach Desktop's zenoh-gateway (it's behind Desktop's login
when `desktop.password_hash` is set) can subscribe to every app's frontend keys and to Desktop's events, and anything on
the zenoh network can publish on them. Don't put secrets in events. Per-app tokens (zenoh-gateway's authorize hook,
granting each app's pages `<ns>/apps/<name>/**` only) come later. Until then every page also gets what zenoh-gateway 0.5
added: queryables (answering `get`s on any key) and liveliness tokens.

## What went away

- `GET /api/events` (SSE): replaced by `<ns>/desktop/events/**` and `<ns>/dimos/events/**`. Kept, **deprecated and
  internal**, for one release, for clients not yet moved (the dim-app SDK's `onDesktopEvent`, the agent's page); removed
  after.
- `GET /api/jobs/<id>` (SSE): replaced by `<ns>/desktop/jobs/<id>` + `GET /api/jobs/<id>/log`. Removed.
- `/api/windows/ws` (websocket): replaced by the `/api/windows/<id>` POSTs + `<ns>/desktop/windows/<id>`. Removed.
