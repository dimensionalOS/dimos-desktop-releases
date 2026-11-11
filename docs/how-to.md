# How to: Desktop's API from an app

Snippets run in an app's page (served at `/apps/<name>/`) with [dim-app](https://github.com/dimensionalOS/ddtk) vendored
as `./dim-app/`. Each `uses:` line goes in the app's `dimos.yaml`:

```yaml
uses:
    "@desktop-gateway":
        - POST /api/notifications # one line per call, as below
```

Full reference: [api.md](api.md).

## How do I send a notification?

```js
import { notify } from "./dim-app/mod.js"

notify({ title: "Map saved", body: "office_2f.pgm", kind: "ok" }) // kind: ok | warn | agent | events
notify({ title: "Robot fell", kind: "warn", sound: "urgent", actions: [["Open", "open:my-app/#fall"]] })
// more than a banner holds: a modal with markdown, a log, Copy, and its own buttons (kept with the notification)
notify({
    title: "Calibration failed",
    body: "camera 2 didn't answer",
    kind: "warn",
    actions: [["Show details", "modal:details"], ["Retry", "post:/apps/my-app/api/calibrate"]],
    modals: {
        details: {
            body: "**camera 2** timed out after 5 s.\n\n- check its cable\n- `ls /dev/video*`",
            pre: logTail, // monospace, scrolled to the end
            copy: true, // a Copy button for body + pre
            actions: [["Retry", 'post:/apps/my-app/api/calibrate {"camera":2}'], ["Close", "close"]],
        },
    },
})
```

Action kinds and the modal fields: [api.md](api.md#notification-actions-and-modals).

```yaml
- POST /api/notifications
- GET /api/apps/{app}/icon
```

Raw:
`fetch("/api/notifications", { method: "POST", body: JSON.stringify({ title, body, kind, sound, actions, modals }) })`.

## How do I open another app?

```js
import { openApp } from "./dim-app/mod.js"

await openApp("dim-controller", { path: "#record" }) // install name or title; built-ins: launcher, appstore, settings
```

```yaml
- GET /api/apps
- GET /
```

## How do I open the Launcher with filters?

```js
await openApp("launcher", { stream: "cmd_vel", robot: "go2" }) // also query, selected (a blueprint)
```

Same as the link `/?app=launcher&needs=cmd_vel&robot=go2` (also `q=`, `blueprint=`).

## How do I run a shell command (sudo too)?

```js
import { runCommand, runShell } from "./dim-app/mod.js"

const result = await runShell({
    title: "Fix LAN discovery",
    commands: [
        { run: "sudo route -n add -host 231.1.1.1 -interface en0", note: "Send the probe over Wi-Fi" },
        { run: "route -n get 231.1.1.1", note: "Check the route", needsStdout: true },
    ],
})
// result.status: succeeded | failed | cancelled; result.commands[i].stdout
const { stdout } = await runCommand("id -u", { title: "Who am I", needsStdout: true })
```

```yaml
- POST /api/desktop/shell
- GET /api/desktop/shell/{id}
- POST /api/desktop/shell/{id}/cancel
```

The user presses Run in Desktop's terminal; sudo asks there. Details: [shell.md](shell.md).

## How do I listen to Desktop events?

Page (zenoh):

```js
import { getZenoh } from "./dim-app/mod.js"

getZenoh().subscribeDesktop("apps", (event) => reloadApps()) // "*" = every type; types: events.md
```

```yaml
- GET /api/desktop/zenoh
"@zenoh-gateway": ">=0.5.1" # beside "@desktop-gateway", not under it
```

Deno backend (SSE, deprecated):

```js
import { onDesktopEvent } from "./dim-app/mod.js"

onDesktopEvent("notification", (event) => console.log(event))
```

```yaml
- GET /api/events
```

## How do I set or get an app's icon?

Set: put `icon.svg` at the app repo's root. Get:

```js
const iconUrl = "/api/apps/dim-controller/icon"
```

```yaml
- GET /api/apps/{app}/icon
```

## How do I report an error to Desktop's agent?

```js
import { captureErrors, reportError } from "./dim-app/mod.js"

captureErrors() // uncaught errors + rejections
reportError("Couldn't save the map", error.stack, { level: "error" })
```

```yaml
- POST /api/errors
```

## How do I send a message from my page to my backend?

```js
import { DimAppFrontend } from "./dim-app/mod.js"

new DimAppFrontend().send("setGoal", 350) // backend: new DimAppBackend().onReceive((kind, payload) => ...)
// or plain HTTP to the app's own server:
await fetch("api/goal", { method: "POST", body: JSON.stringify({ goal: 350 }) })
```

No `uses:` line: an app's own routes are its own.

## How do I push from my backend to my page?

Backend:

```js
import { publishFrontend } from "./dim-app/mod.js"

publishFrontend("status", { battery: 0.82 })
```

```yaml
- POST /desktop/frontend/{app}/{topic}
```

Page:

```js
getZenoh().subscribeFrontend("status", (status) => render(status))
```

```yaml
- GET /api/desktop/zenoh
```
