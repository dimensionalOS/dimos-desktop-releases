# Apps

New to apps? Start with the for-humans guide, [create-apps/index.md](create-apps/index.md), and its three example repos.
This page is the reference.

An app is a git repository with a `dimos.yaml` at its root. Desktop clones it to `~/.dimos/apps/<name>`, builds it with
nix, and shows it in the side rail.

`~/.dimos/apps/` may also hold non-app packages (modules); only a folder with an `icon.svg` or a `frontend/` is an app
and appears in Desktop (an error if it's broken), anything else is skipped.

```sh
dimos-desktop install --name my-app https://github.com/me/my-app        # newest version tag, else the default branch
dimos-desktop install https://github.com/me/my-app --ref some-branch    # name defaults to the repo's
dimos-desktop update my-app      # pull the branch (or move to the newest tag), rebuild
dimos-desktop checkout my-app v1.2.0
dimos-desktop uninstall my-app
dimos-desktop list
```

When Desktop is running these go through it (the App Store shows the same job, live); otherwise they run directly.

## What an app repo needs

- `dimos.yaml` at the root (below)
- `icon.svg` at the root (the rail icon)
- `flake.nix` with a `dimosApp` package: Desktop runs `nix build .#dimosApp --out-link result` after every install,
  update and checkout (unless a `nix.cache` prebuilt downloads). Its output is one of:
  - a directory with an `index.html`: a single-page app, served as is at `/apps/<name>/`
  - `bin/dimos-app-server`: Desktop starts it, restarts it with backoff when it exits, and forwards everything under
    `/apps/<name>/` to it (websockets too)
- or, for a static app only, no `flake.nix` and a `frontend/index.html`: Desktop builds nothing and serves only the
  `frontend/` folder, as is, at `/apps/<name>/` (nothing else in the repo is reachable: not `dimos.yaml`, the README or
  `.git/`; dotfiles inside `frontend/` aren't served either; `caches:` and `nix:` are ignored). A repo with a flake.nix
  is always built, even with a `frontend/index.html`. An `index.html` at the root with no flake isn't an app: it's
  refused (a static app keeps its page in `frontend/index.html`).

An app is one repo; its name is the name it was installed under (`--name`, else the repo's name).

## dimos.yaml

```yaml
title: Live Viewer # rail label; defaults to the app's name
spec-version: v1.2 # REQUIRED: the dimos.yaml spec this file follows (how the rest of it is read; this Desktop: v1.2)
provides: # what the app offers under /apps/<name>/
    description: "Live camera and map views of the robot" # for the agent
    endpoints: # PUBLIC: the agent and other apps may call these
        - method: POST
          path: api/open # relative to the app
          description: Open a recording by id
          params:
              id: { type: string, description: the recording's id }
    private: # what its server answers only its own pages ([METHOD] path, relative; a last * covers what's below)
        - api/internal/*
        - GET api/debug
uses: # everything it calls outside itself; something that isn't there stops the install (Install anyway)
    "@dimos-gateway": # dimos's API; paths relative to /dimos
        version: ">=0.0.14b1" # optional: the dimos versions it works with
        endpoints: [GET /blueprints, POST /runs]
    "@desktop-gateway": [POST /api/notifications, GET /recordings] # Desktop's own API (api.md); full paths
    "@agentic-gateway": [GET /api/status] # the agent (dimcode); paths relative to /agent
    "@zenoh-gateway": ">=0.5 <0.6" # it uses the zenoh-gateway: the versions it works with
    dim-rerun: [POST api/open] # any other name: that app's public endpoints, relative to /apps/<name>/
zenoh: # spec v1.2: what its pages may read and write through the zenoh-gateway; without it, nothing (below)
    default_permission: deny # what no rule decides gets (allow or deny), as in zenoh's ACL
    read: # what reaches the page
        - id: robot-state # each rule's own name
          messages: [declare_subscriber, put, query, reply] # subscribe (and get its samples), `get` (and its replies)
          key_exprs: ["*/odom", "*/color_image", "camera/**"]
          permission: allow
        - id: no-raw-depth
          messages: [put] # samples on these keys never reach the page
          key_exprs: ["camera/*/depth_raw"]
          permission: deny # a deny always wins
    write: # what the page sends out
        - id: drive
          messages: [put] # publish (session puts and publishers)
          key_exprs: [cmd_vel]
          permission: allow
connects: # origins outside Desktop its pages fetch from or open websockets to (any iframe is allowed without this)
    - ws://*:9876 # any machine, port 9876
caches: # optional: binary caches holding this app's builds; Desktop's nix builds use them once nix.conf trusts them
    - {
          url: https://dimos-desktop.cachix.org,
          key: "dimos-desktop.cachix.org-1:A4P35aGJGmCan92LWyamtSFXMqaVE+VRFYnrJ8QMTeQ=",
      }
nix: # optional: prebuilt builds Desktop downloads (if a cache above has them) instead of building dimosApp
    cache:
        aarch64-linux: # nix's name for the machine type that tries these, in order, download only
            - packages.aarch64-darwin.dimosApp-aarch64-linux # a cross build made on a Mac
            - packages.x86_64-linux.dimosApp-aarch64-linux
```

`nix.cache` exists because a binary cache is keyed by the recipe, not the app: an arm robot's own `.#dimosApp` is a
different recipe from a Mac's cross build of it, so the robot misses the cache even when the Mac pushed the cross build.
Listing the Mac's attribute by its full path lets the robot download exactly that. Desktop tries each entry for its
machine type with `--max-jobs 0` (download only: a miss fails in seconds and nothing is built), then builds `dimosApp`
as usual.

`provides:` is what the app serves: `description` and `endpoints` (each `{method, path, description, params}`, `path`
relative to the app) are its public API, what the agent sees ([agent.md](agent.md)); `private` lists the rest of what
its server answers, for its own pages only. A key other than these three is passed to the agent manifest as is.

`uses:` maps a name to what the app calls there. The names:

| name                 | what                                      | its paths are                                          |
| -------------------- | ----------------------------------------- | ------------------------------------------------------ |
| `"@dimos-gateway"`   | dimos's API                               | relative to `/dimos` (`GET /runs` is `/dimos/runs`)    |
| `"@desktop-gateway"` | Desktop's own API ([api.md](api.md))      | as Desktop serves them (`/api/...`, `/recordings/...`) |
| `"@agentic-gateway"` | the agent, dimcode ([agent.md](agent.md)) | relative to `/agent` (`GET /api/x` is `/agent/api/x`)  |
| `"@zenoh-gateway"`   | the zenoh-gateway (below)                 | none: a version range only                             |
| any other name       | that installed app's public endpoints     | relative to `/apps/<name>/` (`GET api/status`)         |

Each value is one of:

- a list of endpoints, `METHOD path` (`{param}` for a path parameter: `GET /runs/{runId}/log`);
- a version range string (`">=0.5 <0.6"`): what `@zenoh-gateway` usually is; on `@dimos-gateway` it's the dimos versions
  the app works with;
- a map, `{version: <range>, endpoints: [...], optional: true}`, each optional (another field, from a newer spec, is
  ignored with a warning). `optional: true` (spec v1.1, on another app only) says the app works without that one: it not
  being installed isn't a problem (the app should check `GET /api/apps` before calling it);
- nothing (`"@zenoh-gateway":`): used, any version.

A version is checked for `@dimos-gateway` (the installed dimos) and `@zenoh-gateway` (the bridge Desktop runs); on
another name it's ignored with a warning, and so are endpoints on `@zenoh-gateway`. A leading `/` (or `./`) on a
relative path is optional. Names starting with `@` are quoted (YAML reserves `@`). An `@name` this Desktop doesn't know
(from a newer spec) is ignored with a warning, like an unknown key; another app's name that isn't installed is a missing
app (below). Calls to the app's own server (under `/apps/<name>/`, websockets included) aren't listed in `uses:`;
they're what it `provides:`. Each endpoint is checked against what is actually there:

- `@dimos-gateway`: the installed dimos gateway's OpenAPI document, which its dimos.yaml names (`api: openapi:`); a
  dimos without one is checked against Desktop's list of the gateway's endpoints.
- another app: it must be installed, and if its `provides:` lists endpoints, serve this one (never a private one).
- `@desktop-gateway`, `@agentic-gateway`: Desktop's own endpoints.

Also checked: `spec-version:`, the dimos version (any `@dimos-gateway` entry needs dimos installed) and `@zenoh-gateway`
(the bridge on, and in range). An install, update or version switch that fails a check stops before anything is built,
lists what's missing, and offers **Install anyway** (`dimos-desktop install --force`, `update
--force`,
`checkout --force`; the API's `force: true`); an update that stops puts the clone back where it was. That override is
how two apps that call each other get installed: the first goes in anyway, then the second passes. The App Store marks
an app installed that way incompatible and lists its problems in App info until they're gone. A bad shape (`/dimos/runs`
without a method) fails the install outright; an unknown key doesn't (it's ignored with a warning, see "Compatibility"
below). A declared cache only takes effect once nix.conf trusts it (the install job and the App Store say so and give
the one sudo command; the dimOS caches are trusted by the installer); otherwise the app builds from source. The list is
checked when the app is installed, updated or switched and shown in the App Store, and enforced at runtime (below).

### `zenoh:` (spec v1.2): what an app's pages may do on zenoh

A page that uses the zenoh-gateway may do on zenoh only what its app's `zenoh:` section allows. The section is
[zenoh's own access-control config](https://zenoh.io/docs/manual/access-control/), decided the same way, for one subject
(the app): `default_permission` (`allow` or `deny`, required) and rules with zenoh's fields, all required but `flows`:
`id` (unique), `messages`, `flows`, `key_exprs` and `permission` (`allow` or `deny`). The rules are listed twice:
`read:` (what reaches the page) and `write:` (what the page sends out).

A message is decided like zenoh decides it: **denied** when a `deny` rule for that message and flow includes its key;
otherwise **allowed** when `default_permission` is `allow` or an `allow` rule includes it; otherwise denied. The zenoh
gateway stands where zenoh's router would: **ingress** is what the page sends, **egress** what the gateway hands it.

| list     | message (flow)                                                                             | decides                                                                        |
| -------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| `read:`  | `declare_subscriber` (ingress)                                                             | opening a subscription on a key expression                                     |
| `read:`  | `put`, `delete` (egress)                                                                   | each sample (by its key) a subscription receives                               |
| `read:`  | `query` (ingress), `reply` (egress)                                                        | `get` (and queriers) on a key expression; each reply (by its key)              |
| `read:`  | `declare_liveliness_subscriber`, `liveliness_query` (ingress), `liveliness_token` (egress) | watching liveliness, `livelinessGet`; each token (by its key) they report      |
| `write:` | `put` (ingress)                                                                            | session `put`, publishers (and deadmen), leases, a publisher's matching status |
| `write:` | `delete` (ingress)                                                                         | session `delete`                                                               |
| `write:` | `declare_queryable` (ingress), `query` (egress), `reply` (ingress)                         | declaring a queryable; each query it receives; each reply it sends             |
| `write:` | `liveliness_token` (ingress)                                                               | declaring a liveliness token                                                   |

`put`, `delete`, `reply`, `query` and `liveliness_token` appear on both lists, one flow each, as in zenoh: `put` under
`read:` is a sample reaching the page (egress), under `write:` the page's own put (ingress). `flows:` may be left out
(each message takes its own flow on its list); when it is there it must hold exactly the flows its messages take (`put`
under `read:` is egress, under `write:` ingress). A message on the wrong list (`declare_queryable` under `read:`), a
missing field, a repeated `id` or a key expression zenoh wouldn't take as written (`a//b`, `a/**/**`) is a bad shape
that fails the install.

`key_exprs` are zenoh key expressions: `*` is one chunk, `**` any number (`robot/*/odom`, `camera/**`); a rule decides a
message when one of its expressions includes the message's key (`camera/**` includes `camera/front/image` and
`camera/front/**`, not `camera`, nor `**`: a subscription to `**` needs a rule on `**` or `default_permission: allow`).
A request (subscribing, putting, querying, ...) the rules deny is **refused**; a sample, reply, query or token they deny
on its way to the page is **dropped**, silently, as zenoh drops it. `listTopics` shows the keys the page could subscribe
to or query. Desktop's own keys sit under its namespace (`dimos-desktop/<host>-<port>/...`, [events.md](events.md)): an
app that listens there lists e.g. `dimos-desktop/*/desktop/events/**` or `dimos-desktop/*/apps/<name>/frontend/**`.

What an app gets, by its `spec-version:`:

- **v1.0, v1.1:** read and write on `**`, everything (as before v1.2). A `zenoh:` section in such a file isn't applied
  (a warning says to write `spec-version: v1.2`).
- **v1.2 (or a newer v1.x) with `zenoh:`:** exactly what its rules and default decide.
- **v1.2 without `zenoh:`:** nothing: every subscription, put, query, ... is refused. Everything has to be listed, even
  `**` (`default_permission: allow`, or an allow rule on `"**"`).

`zenoh:` decides what pages may do; `uses: "@zenoh-gateway"` (its version range) is still what lets them reach the
gateway at all, and a v1.2 file with rules but without it gets a warning. A refused request fails in the page with
`not authorized to <action> "<key>"` (the client's promise rejects, a subscription or publisher ends up `rejected`) and,
like any refused call, posts one notification per app and rule whose action shows the rule to add (see "The dimos.yaml
check").

**Whose a connection is.** The gateway decides this when a page (or server) connects, and refuses a connection it can't
attribute:

- a page under `/apps/<name>/`, by its Referer: that app's rules (an app that isn't installed: refused);
- one of Desktop's own pages (a Referer on Desktop's origin outside `/apps/`): everything;
- an app's server, by the bearer token Desktop hands it as `zenohGatewayToken` in `DIMOS_APP`
  (`connect(url, { token })`): that app's rules (a token Desktop didn't make: refused);
- anything else (no Referer, as with `referrerPolicy: "no-referrer"`, another origin's, no token): refused, 401.

Every app shares Desktop's origin, so a page that sets its fetches' `referrer` to another page of the same origin can
still pass for it: the rules stop an app from using zenoh outside its dimos.yaml by accident or by leaving its Referer
out, not an app written to impersonate another (that needs each app on its own origin).

The rules are enforced by the zenoh-gateway Desktop embeds (0.5.6 and later). While Desktop proxies to an external
`zenoh-gateway` (`zenoh_gateway.external_port`), which knows neither, only connections Desktop would give everything
(Desktop's own pages, apps on v1.0/v1.1) go through; a v1.2 app's page gets a 403 saying why, an unattributed one a 401.

### Compatibility: dimos.yaml never breaks

- **Additive only.** A new feature is a new optional key (or a new optional field inside one). A key is never removed or
  given a different type or meaning; nothing that parses today stops parsing.
- **Replaced keys keep working.** Before `provides:` and `uses:`, the same things were `agent:` (now `provides:`'s
  description and endpoints), `private:` (`provides: private`), `dimos-api:` (`uses:`, full paths: `GET /dimos/runs`,
  `POST /api/notifications`, `GET /apps/<name>/api/x`), and `dimos:` (`uses: "@dimos-gateway": {version}`). They're
  still read, into the same thing, with a deprecation warning (and an `app check` finding); a file may mix both
  (endpoints of both count; for a version range, `uses:` wins).
- **Unknown keys are ignored.** A Desktop that doesn't know a key (or a `uses:` `@name`) installs the app anyway and
  shows a warning ("`<key>:` is newer than this Desktop knows"). An app written for a newer Desktop still installs on an
  older one.
- **`spec-version: vMAJOR.MINOR` names the spec the file follows.** Each added key bumps the minor (v1.1, ...); a major
  bump (v2.0) would mean a break, which isn't expected. Desktop reads its own major: a file at a newer minor installs
  (its newer keys are ignored, with a note to update Desktop); a different major is refused like any failed check
  (**Install anyway** forces it); a malformed one (`v1`, `1.0`) is a bad shape. The old `dimos-desktop-api:` range is
  deprecated: read as v1.0, with a warning (so is a file with neither key).
- Desktop's tests parse every dimos.yaml shape apps have shipped (`old_and_future_dimos_yamls_parse`); add yours when
  you add a key.

## The dimos.yaml check

An app's dimos.yaml says what it **offers** under `/apps/<name>/` and what it **requires** outside itself, and Desktop
holds it to both while it runs (`src/server/contract.rs`):

- **Offers.** Its `provides:` endpoints are its public API (in full: other apps and the agent may call them). Whatever
  else its server answers its own pages on (`api/...` paths and websockets) goes under `provides: private`, without a
  definition: `GET api/debug`, or `api/internal/*` (a last `*` covers everything below; no method means any). Private
  endpoints are its own pages' only: the agent, the endpoint list and OpenAPI never show them, and no other app may call
  them (an install that requires one stops as incompatible).
- **Requires.** `uses:` lists every endpoint it calls outside itself (the dimos gateway's, Desktop's, the agent's,
  another app's public ones), and `"@zenoh-gateway"` says it uses the bridge (its websocket and the SDK's
  `GET /api/desktop/zenoh` that finds it). What it may do on zenoh through the bridge is `zenoh:` (spec v1.2, above);
  the gateway refuses the rest and reports it here, as direction `zenoh`, with the `zenoh:` rule to add. The dim-app
  SDK's own calls (`POST /api/errors`, `GET /api/ui-settings`, `GET /api/ui-settings/themes`) need no entry.
- **Connects.** Its pages get a Content-Security-Policy: `connect-src` is Desktop itself (as the browser reached it, so
  remote forwards work) plus the `connects:` origins, `frame-src *`. Any iframe is allowed; a fetch or websocket
  anywhere else is blocked by the browser. An install or update that adds a `connects:` origin stops first and lists
  them, like a permission ("Allow and install").

A call from an app's page that its dimos.yaml doesn't declare (its own undeclared endpoint, an undeclared outside one,
another app's private one) is **refused** with a 403
(`{error, dimosYamlCheck: {app, direction, endpoint, line,
key, file, snippet, explanation, message}}`) and posts one
notification per app and endpoint (while Desktop runs); its action opens what to change: the explanation, the YAML to
add (in this shape, under the right `uses:` name: `uses: {"@dimos-gateway": [POST /runs]}`) and where, and **Copy
message**, the same as a prompt for an agent. App info lists what the app offers, requires and connects to, and its
refused calls; the App Store marks the app. `GET /api/apps/<name>/dimos-yaml-check` and `GET /api/dimos-yaml-check/<id>`
are the same over HTTP.

Which app a call is from is its Referer: a page under `/apps/<name>/` on the same origin. That makes undeclared calls
hard to make by accident, not impossible on purpose: what sends no Referer, or another one, isn't judged — Desktop's own
pages (`/`), the agent and MCP calls, app servers (their calls to Desktop carry none), websocket handshakes (browsers
send no Referer on them), and a page that drops or changes its own (`referrerPolicy: "no-referrer"`, fetch's `referrer`
option). Resource loads (pages, frames, scripts, images) aren't judged either: only fetches and websockets.

`dimos-desktop app check <repo dir | installed app>` runs the same check before the app does: its dimos.yaml parses,
nothing it requires of an installed app is private there, and its source (string literals in its `.js/.ts/.py/...`,
outside tests) names no endpoint or outside origin its dimos.yaml doesn't declare (each reported with the `uses:` name
it goes under), and it uses no deprecated key or unknown `@name`. It exits 1 when it finds something (for an app's CI).
It reads literals, so a path built at runtime can slip past it; the runtime check is the rule.

`--run` also starts its built server (`./result/bin/dimos-app-server`, so `nix build .#dimosApp` first; a build is too
slow to do by default) exactly as Desktop does (no arguments, the same `DIMOS_APP` with a scratch `socket` and
`dataDir`, the repo as cwd) and fails unless it listens on that socket and is still running after 5 s (it gets 30 s to
start listening). Desktop runs the same start check on every install, update and checkout of a server app, before the
new build replaces the running one: a server that won't start fails the job with what it printed, and the app stays
where it was.

Apps are served at `/apps/<name>/`, so they use relative URLs (`fetch("../../dimos/runs")`,
`new URL("ws", location.href)`).

## `dimos-app-server`

Desktop starts it with no arguments and one environment variable, `DIMOS_APP`, whose value is a JSON object: everything
Desktop tells the app. It is the whole interface: no flags, no other variables.

```json
{
    "version": 3,
    "name": "dim-controller-v2",
    "socket": "/Users/me/.dimos/desktop/sockets/dim-controller-v2.sock",
    "url": "http://127.0.0.1:7341/apps/dim-controller-v2/",
    "path": "/apps/dim-controller-v2/",
    "dataDir": "/Users/me/.dimos/data/apps/dim-controller-v2",
    "desktopUrl": "http://127.0.0.1:7341",
    "zenohGatewayUrl": "http://127.0.0.1:7341/zenoh-gateway",
    "zenohGatewayToken": "dim-controller-v2.6f1c…",
    "zenohConnect": "tcp/10.0.0.2:7447",
    "zenohNamespace": "dimos-desktop/my-mac-7341",
    "zenohPrefix": "dimos-desktop/my-mac-7341/apps/dim-controller-v2",
    "dimosDir": "/Users/me/dimos",
    "dimosPython": "/Users/me/dimos/.venv/bin/python",
    "recordingsDir": "/Users/me/.dimos/recordings"
}
```

- `version`: the shape of this object (3: `dimosPython` may be null). New fields can appear without a bump; one changing
  meaning or going away bumps it.
- `name`: the name the app was installed under. Two installs of one repo (`--name a`, `--name b`) are two apps, each
  with its own `name`, `socket`, `url`, `path` and `dataDir`.
- `socket`: serve HTTP on this unix socket. Requests arrive with `path` (minus its trailing `/`) removed.
- `url`, `path`: the app's own address, `path` being where Desktop serves it (`/apps/<name>/`) and `url` that path on
  Desktop's loopback origin (`desktopUrl`). Desktop answers on many origins (localhost, the LAN, a tailnet, a tunnel)
  and can't know which one a given browser uses, so `url` is the one that always works from the app's own machine; for
  links shown to a user, the page's `location` is the right origin.
- `dataDir`: the app's own writable folder (`~/.dimos/data/apps/<name>`, created for it). Its checkout is a git clone
  that updates replace, so files go here.
- `desktopUrl`: Desktop's own HTTP base (for `/dimos/...`).
- `zenohGatewayToken`: the bearer token this app's server connects to the zenoh-gateway with
  (`connect(zenohGatewayUrl, { token })`); it gets the app's `zenoh:` access, and a connection without one (or a page's
  Referer) is refused.
- `zenohGatewayUrl`: Desktop's zenoh-gateway. `zenohConnect`: the zenoh endpoint dimos modules are on (empty = peer on
  the local network), for a server that talks zenoh itself.
- `zenohNamespace`: Desktop's zenoh namespace (`desktop.namespace`); `zenohPrefix`: `<zenohNamespace>/apps/<name>`, this
  install's own keys. The app's pages hear its backend on `<zenohPrefix>/frontend/<topic…>`: publish there directly, or
  `POST ${desktopUrl}/desktop/frontend/${name}/<topic…>` and Desktop publishes the body ([events.md](events.md)).
- `dimosDir`, `dimosPython`: the dimos checkout Desktop uses and the python dimos runs with, as the dimos gateway's
  `GET /dimos/python` says when the app starts (null when the gateway couldn't say; ask it again then).
- `recordingsDir`: the shared recordings folder.

```js
const app = JSON.parse(Deno.env.get("DIMOS_APP"))
Deno.serve({ path: app.socket }, handler)
```

It runs with the repo as its cwd, in its own process group (with `DIMOS_RECORDINGS_DIR` set too: that one is for dimos
itself, when the app starts it), and its output is kept in a bounded buffer shown in the App Store (never the service
log).

## A minimal flake

A static app:

```nix
{
    inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    outputs = { self, nixpkgs }: {
        packages.aarch64-darwin.dimosApp = nixpkgs.legacyPackages.aarch64-darwin.runCommand "my-app" { } ''
            cp -r ${self}/frontend $out
        '';
        # ...same for x86_64-darwin, x86_64-linux, aarch64-linux
    };
}
```

A vite build, a Rust server or a Python one is any derivation with the output shape above. For apps on the
[dim-app SDK](https://github.com/jeff-hykin/dim-app), its flake's `mkDimosApp` builds either shape:

```nix
{
    inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    inputs.dim-app.url = "github:jeff-hykin/dim-app/v0.5.0";
    outputs = { self, nixpkgs, dim-app }: {
        packages = dim-app.lib.forAllSystems nixpkgs (pkgs: {
            dimosApp = dim-app.lib.mkDimosApp {
                inherit pkgs;
                src = self;
                frontend = "dim/apps/my_app/frontend";
                backend = "dim/apps/my_app/main.js"; # optional; makes a dimos-app-server
            };
        });
    };
}
```

Add `result` to `.gitignore`.

## Talking to dimos modules: zenoh-gateway

dimos's default transport is zenoh. Desktop embeds [zenoh-gateway](https://github.com/jeff-hykin/zenoh-gateway) (with
the [ROS 2 / dimos codecs](https://github.com/jeff-hykin/zenoh-dimos-codecs)), so a page can subscribe to any module's
stream (camera images arrive as H.264 video, point clouds quantized, depth lossless), publish (with a deadman for
commands), `get`, answer queries and use liveliness without a dimos-version-specific SDK. Declare
`uses: "@zenoh-gateway": <range>` in dimos.yaml and connect with the client at the commit Desktop embeds. A page reaches
the gateway at the fixed same-origin path `/zenoh-gateway`, i.e. `../../zenoh-gateway` from `/apps/<name>/`:

```js
import { connect } from "https://esm.sh/gh/jeff-hykin/zenoh-gateway@dc00dd7/client/zenoh_gateway.ts"
const zenoh = await connect(new URL("../../zenoh-gateway", location.href).href)
```

An app server gets the gateway's URL as `zenohGatewayUrl` in `DIMOS_APP` (and the zenoh endpoint as `zenohConnect`).
Topic names and encodings: zenoh-gateway's SPEC.md, and `zenoh.encodings` lists what the gateway runs.
`GET /dimos/blueprints/<name>` lists each module's streams.

What a page may do there is its app's `zenoh:` section (spec v1.2, "`zenoh:`" above): an app on spec v1.0 or v1.1 gets
the whole zenoh API on any key; a v1.2 app gets exactly the subscriptions, puts, queries, queryables and liveliness its
rules list, and nothing without them.

## Backend → page: events over zenoh

An app's server pushes to its pages over zenoh, never its own websocket or SSE:
`POST
${desktopUrl}/desktop/frontend/${name}/status` with a JSON body, and every open page of the app subscribed to
`<zenohPrefix>/frontend/**` (on its one zenoh-gateway connection) gets it. Pages ask the app's server over plain HTTP,
and get the namespace from `GET ../../api/desktop/zenoh?app=<name>`. The keys, sizes and the snapshot + live pattern:
[events.md](events.md).

## The page and the shell: insets, opening apps

An app's page runs in an iframe that fills Desktop's app layer. On a desktop-width window the shell's bottom bar (the
chat box at its left, the blueprint in its middle, the dock at its right) sits over the frame's bottom edge; the shell
posts how much as `{type: "dimos-inset", top, bottom, left, right}`, which becomes `--dim-inset-*`: keep controls above
`var(--dim-inset-bottom)`. Theme, corners and insets (apps look like Desktop in every skin, from Desktop's `/theme.css`
tokens, with no theme switch of their own): [create-apps/themes.md](create-apps/themes.md).

A page opens another app (or a built-in: `launcher`, `appstore`, `settings`) in the same window with
`parent.postMessage({dimosShell: 1, type: "open_app", app, path}, location.origin)`; `app` is the install name. From a
backend, or a page outside the shell, it's `POST /api/open-app` (the window the user used last, [agent.md](agent.md)).
To open the Launcher filtered, give it a deep-link path: `{…, app: "launcher", path: "?needs=cmd_vel"}` (blueprints with
a module whose input or output name contains it, e.g. `tele_cmd_vel`; also `q=`, `robot=`, `blueprint=` to select one,
`all=1`; a link sets what it names and clears the other filters). dim-app's `openApp(id, params)` and `appInstalled(id)`
wrap this (`openApp("launcher", { query, robot, stream, selected })` puts those in the link as `q`, `robot`, `needs`,
`blueprint`). A plain link works too: `/?app=launcher&needs=cmd_vel` ([launcher.md](launcher.md)). An app opened this
way (or by `POST /api/open-app`) remembers what opened it: closing or minimizing it goes back to that app if it's still
open, through a chain; an app the user picks (dock, search, a card) starts fresh (`ui/src/shell/appOpeners.ts`).

The shell draws an app's page into an image for the agent's `screenshot` and for its card when it's minimized
(`ui/src/shell/frameCapture.ts`): the page, each `<video>`'s current frame, each canvas and each same-origin iframe, as
on screen. Canvases are copied in a frame right after the page draws, so a WebGL canvas without `preserveDrawingBuffer`
comes out too, as long as the page draws within 0.4 s. A page that draws only on change (a dirty flag) draws once when
asked, or its 3D comes out empty while nothing moves: `addEventListener("dimos-capture", () => viewer.requestRender())`.

## Shell commands (sudo too)

An app never runs privileged commands itself: it asks Desktop with `POST /api/desktop/shell` (a title, a message, and
commands with a note each). Desktop shows them over the app, the user presses Run, they run in one terminal (sudo asks
once), the agent can help when one fails, and the app polls for each command's exit code and output. dim-app's
`runShell()` does it in one call. [shell.md](shell.md).

## Apps with a Deno backend: the dim-app SDK

[dim-app](https://github.com/jeff-hykin/dim-app)'s `mkDimosApp` (above) builds a `dimos-app-server` that serves the
frontend, runs the backend module in-process and bridges the two over its own websocket; Desktop only forwards to it.

## Versions

Versions are git tags matching `vX.Y.Z` (or `X.Y.Z`). Install checks out the newest tag unless `--ref` is given; any tag
or branch can be picked from the App Store's version menu.

A tag with anything after the `X.Y.Z` core is a **beta** (`v1.1.1-beta`, `v1.1.1rc1`, `v1.1.1blah`). Install, Update and
Update all never move to a beta; it shows (labelled beta) in the version menu for testers to pick. An app on a beta
updates to the next newer stable tag (`v1.1.1` is newer than `v1.1.1-beta`), never to another beta. Order within one
core: other suffixes < `a` < `b` < `rc` < the release.
