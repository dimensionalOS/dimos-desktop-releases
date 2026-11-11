# Apps

New to apps? Start with the for-humans guide, [create-apps/index.md](create-apps/index.md), and its three example repos.
This page is the reference. Keeping an app current with a newer Desktop: [changelog.md](changelog.md).

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
spec-version: v1.5 # REQUIRED: the dimos.yaml spec this file follows (how the rest of it is read; this Desktop: v1.5)
provides: # the app's own API under /apps/<name>/, as an OpenAPI 3.1 document (spec v1.3)
    openapi: 3.1.0
    info:
        title: Live Viewer
        version: 1.0.0
        description: Live camera and map views of the robot
        x-when: you need to see what a robot's cameras see, or open a recording # for the agent
    paths: # PUBLIC: the agent and other apps may call these
        api/open: # relative to the app
            post:
                description: Open a recording by id
                x-when: the user names a recording to look at
                parameters:
                    - { name: id, in: query, description: the recording's id, schema: { type: string } }
    x-private: # what its server answers only its own pages ([METHOD] path, relative; a last * covers what's below)
        - api/internal/*
        - GET api/debug
uses: # everything it calls outside itself; something that isn't there stops the install (Install anyway)
    "@dimos-gateway": # dimos's API; paths relative to /gateways/dimos
        version: ">=0.0.14b1" # optional: the dimos versions it works with
        endpoints: [GET /catalog/blueprints, POST /active/launch]
    "@desktop-gateway": # Desktop's own API (api.md); paths relative to /gateways/desktop
        endpoints: [POST /ui/notifications, GET /recordings]
        env: # spec v1.5: the values it needs of that provider's environment
            DIMOS_APP.machineId: tags the recordings it makes
            DIMOS_APP.dataDir: { required: true, schema: { type: string } }
    "@agentic-gateway": [GET /api/status] # the agent (dimcode); paths relative to /gateways/agent
    "@zenoh-gateway": ">=0.5 <0.6" # it uses the zenoh-gateway: the versions it works with
    "@launcher": [GET api/catalog] # a built-in app (spec v1.4), used like any other
    dim-rerun: [POST api/open] # any other name: that app's public endpoints, relative to /apps/<name>/
zenoh: # spec v1.2: what the app's PAGES may do on the bus; without this section, nothing
    default_permission: deny
    read: # what may reach the page
        - { id: cam, messages: [declare_subscriber, put], key_exprs: ["camera/**"], permission: allow }
    write: # what the page may send out
        - { id: drive, messages: [put], key_exprs: ["robot/cmd_vel"], permission: allow }
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

`provides:` is the app's own API, as an **OpenAPI 3.1 document** (spec v1.3): its `paths` are its public API, what the
agent and other apps may call, and `x-private:` lists the rest of what its server answers, for its own pages only.
Each path is relative to the app. Alongside OpenAPI's own fields, Desktop reads two of its own: `x-when` (on
`info:` for the whole app, and on each operation) is when to use it, one short line read after "If " — `you need to
rename a recording` — and it, with `description`, is what the agents' skill files are built from
([agent.md](agent.md)). The pre-v1.3 shorthand (`provides: {description, endpoints: [{method, path, description,
params}], private: [...]}`, and a top-level `private:`) is still read into the same thing.

`uses:` maps a name to what the app calls there. The names (paths are as of spec v1.4, when Desktop's own API moved
under `/gateways/desktop/`; a file at v1.3 or lower has `@desktop-gateway` paths written in full and the gateways under
`/dimos-gateway` and `/agent-gateway`):

| name                 | what                                      | its paths are                                                            |
| -------------------- | ----------------------------------------- | ------------------------------------------------------------------------ |
| `"@dimos-gateway"`   | dimos's API                               | relative to `/gateways/dimos` (`GET /active` is `/gateways/dimos/active`) |
| `"@desktop-gateway"` | Desktop's own API ([api.md](api.md))      | relative to `/gateways/desktop` (`GET /info/apps`)                       |
| `"@agentic-gateway"` | the agent, dimcode ([agent.md](agent.md)) | relative to `/gateways/agent` (also `"@dimcode-gateway"`)                |
| `"@zenoh-gateway"`   | the zenoh-gateway (below)                 | none: a version range only                                               |
| `"@launcher"`        | a built-in app (spec v1.4)                | relative to `/apps/@launcher/`, like any other app                       |
| any other name       | that installed app's public endpoints     | relative to `/apps/<name>/` (`GET api/status`)                           |

Each value is one of:

- a list of endpoints, `METHOD path` (`{param}` for a path parameter: `GET /runs/{runId}/log`);
- a version range string (`">=0.5 <0.6"`): what `@zenoh-gateway` usually is; on `@dimos-gateway` it's the dimos versions
  the app works with;
- a map, `{version: <range>, endpoints: [...], env: {...}, optional: true}`, each optional (another field, from a newer
  spec, is ignored with a warning). `optional: true` (spec v1.1, on another app only) says the app works without that
  one: it not being installed isn't a problem (the app should check `GET /gateways/desktop/info/apps` before calling
  it);
- nothing (`"@zenoh-gateway":`): used, any version.

### `env:` — the values an app needs of a provider (spec v1.5)

`env:` under a `uses:` name lists what the app needs of **that provider's environment**, keyed by variable or by a path
inside one holding JSON. A bare list works (`env: [DIMOS_APP.machineId]`); a map says more, each value being nothing,
what the app needs it for, or `{required, schema, description}`:

```yaml
uses:
    "@desktop-gateway":
        env:
            DIMOS_APP.machineId: tags the recordings it makes
            DIMOS_APP.secrets.zenohGatewayToken: { required: false, schema: { type: string } }
```

**Declare a field, not the variable.** Every app server is given `DIMOS_APP`, so declaring `DIMOS_APP` says nothing;
what varies is what is *in* it — `machineId` exists only from Desktop 0.2.226, and an app that wrote recordings tagged
with an empty one is the reason this exists. That is also why there is no `DIMOS_APP` version to check instead: the
object is added to without a bump (see `version` below), so only a per-value declaration can answer the question.

`dimos-desktop app check` reports a key `@desktop-gateway` doesn't set, before anything runs. At launch, a value the
app says it needs that Desktop couldn't resolve is written into the app's own log (`warn: DIMOS_APP.x is empty, which
dimos.yaml says this app needs`), and so is a value whose type isn't what `schema:` asks for. Neither is fatal: a
recording missing one field beats no recording. Only `type` in a `schema:` is checked; the rest of a schema is
documentation. A provider whose environment Desktop doesn't know (the dimos gateway, the agent) is accepted and checked
only at launch.

### `zenoh:` — what an app's pages may do on the bus (spec v1.2)

`zenoh:` is zenoh's own [access-control](https://zenoh.io/docs/manual/access-control/) config for this app's pages:
`default_permission` (`allow` or `deny`) plus `read:` (what may reach the page) and `write:` (what the page may send
out), each a list of rules of `{id, messages, key_exprs, permission}`, decided the way zenoh decides them. `messages`
are zenoh's kinds — `put`, `delete`, `declare_subscriber`, `query`, `declare_queryable`, `reply`, `liveliness_token`,
`declare_liveliness_subscriber`, `liveliness_query` — and `key_exprs` are key expressions under the app's namespace.

```yaml
zenoh:
    default_permission: deny
    read:
        - { id: cam, messages: [declare_subscriber, put], key_exprs: ["camera/**"], permission: allow }
    write:
        - { id: drive, messages: [put], key_exprs: ["robot/cmd_vel"], permission: allow }
```

**From spec v1.2 on, a file with no `zenoh:` section gets nothing** — not even read on `**`. A file at v1.1 or lower
gets read and write on `**` whatever it says (a `zenoh:` section there is ignored with a warning), which is what keeps
older apps working. Only an app that may write something is given a zenoh-gateway lease, since a lease can end another
page's subscriptions.

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
an app installed that way incompatible and lists its problems in App info until they're gone. A bad shape (`/active`
without a method) fails the install outright; an unknown key doesn't (it's ignored with a warning, see "Compatibility"
below). A declared cache only takes effect once nix.conf trusts it (the install job and the App Store say so and give
the one sudo command; the dimOS caches are trusted by the installer); otherwise the app builds from source. The list is
checked when the app is installed, updated or switched and shown in the App Store, and enforced at runtime (below).

### Compatibility: dimos.yaml never breaks

- **Additive only.** A new feature is a new optional key (or a new optional field inside one). A key is never removed or
  given a different type or meaning; nothing that parses today stops parsing.
- **Replaced keys keep working.** Before `provides:` and `uses:`, the same things were `agent:` (now `provides:`'s
  description and endpoints), `private:` (`provides: private`), `dimos-api:` (`uses:`, full paths: `GET /dimos/runs`,
  `POST /api/notifications`, `GET /apps/<name>/api/x`; those were Desktop's paths before v1.4), and `dimos:`
  (`uses: "@dimos-gateway": {version}`). They're
  still read, into the same thing, with a deprecation warning (and an `app check` finding); a file may mix both
  (endpoints of both count; for a version range, `uses:` wins).
- **Unknown keys are ignored.** A Desktop that doesn't know a key (or a `uses:` `@name`) installs the app anyway and
  shows a warning ("`<key>:` is newer than this Desktop knows"). An app written for a newer Desktop still installs on an
  older one.
- **`spec-version: vMAJOR.MINOR` names the spec the file follows.** Each added key bumps the minor; a major bump (v2.0)
  would mean a break, which isn't expected. Desktop reads its own major: a file at a newer minor installs (its newer
  keys are ignored, with a note to update Desktop); a different major is refused like any failed check (**Install
  anyway** forces it); a malformed one (`v1`, `1.0`) is a bad shape. The old `dimos-desktop-api:` range is deprecated:
  read as v1.0, with a warning (so is a file with neither key). The minors so far:

  | spec | what it added                                                                                                                |
  | ---- | ---------------------------------------------------------------------------------------------------------------------------- |
  | v1.0 | `provides:` and `uses:` (replacing `agent:`, `private:`, `dimos-api:`, `dimos:`)                                             |
  | v1.1 | `optional: true` on another app in `uses:`                                                                                   |
  | v1.2 | `zenoh:`, what the app's pages may read and write on the bus — **and nothing without it**, where v1.1 had everything         |
  | v1.3 | `provides:` is an OpenAPI 3.1 document, its private paths in `x-private:` (the old shorthand still reads)                    |
  | v1.4 | `uses: "@desktop-gateway"` paths are relative to `/gateways/desktop/`, and built-in apps (`@launcher`) are used like any app |
  | v1.5 | `uses: <name>: env:`, the values an app needs of that provider's environment                                                 |

  Two of those change the meaning of a file rather than only adding a key, so re-stamping a file's `spec-version:`
  without reading them is a mistake: v1.2 turns "every page may do anything on zenoh" into "nothing but what `zenoh:`
  lists", and v1.4 moves what `@desktop-gateway` paths are relative to.
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
  `GET /gateways/desktop/management/gateways/zenoh` that finds it). The dim-app SDK's own calls
  (`POST /gateways/desktop/ui/errors`, `GET /gateways/desktop/settings/ui`,
  `GET /gateways/desktop/settings/themes`) need no entry.
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
refused calls; the App Store marks the app. `GET /gateways/desktop/info/apps/<name>/checks` and
`GET /gateways/desktop/info/checks/<id>` are the same over HTTP.

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

Apps are served at `/apps/<name>/`, so they use relative URLs (`fetch("../../gateways/dimos/active")`,
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
    "zenohGatewayToken": "dim-controller-v2.7f3c…",
    "zenohConnect": "tcp/10.0.0.2:7447",
    "zenohNamespace": "4f1c9b2e8a7d46f0b3e5c1a9d7b2e8a7/default",
    "zenohPrefix": "4f1c9b2e8a7d46f0b3e5c1a9d7b2e8a7/default/apps/dim-controller-v2",
    "dimosDir": "/Users/me/dimos",
    "dimosPython": "/Users/me/dimos/.venv/bin/python",
    "recordingsDir": "/Users/me/.dimos/recordings",
    "machineId": "4f1c9b2e8a7d46f0b3e5c1a9d7b2e8a7",
    "secrets": { "zenohGatewayToken": "dim-controller-v2.7f3c…" }
}
```

- `version`: the shape of this object (3: `dimosPython` may be null). New fields can appear without a bump; one changing
  meaning or going away bumps it — which is why it can't tell you whether a field exists, and why
  `uses: <name>: env:` (above) is how an app says which values it needs.
- `name`: the name the app was installed under. Two installs of one repo (`--name a`, `--name b`) are two apps, each
  with its own `name`, `socket`, `url`, `path` and `dataDir`.
- `socket`: serve HTTP on this unix socket. Requests arrive with `path` (minus its trailing `/`) removed.
- `url`, `path`: the app's own address, `path` being where Desktop serves it (`/apps/<name>/`) and `url` that path on
  Desktop's loopback origin (`desktopUrl`). Desktop answers on many origins (localhost, the LAN, a tailnet, a tunnel)
  and can't know which one a given browser uses, so `url` is the one that always works from the app's own machine; for
  links shown to a user, the page's `location` is the right origin.
- `dataDir`: the app's own writable folder (`~/.dimos/data/apps/<name>`, created for it). Its checkout is a git clone
  that updates replace, so files go here.
- `desktopUrl`: Desktop's own HTTP base (for `/gateways/dimos/...` and `/gateways/desktop/...`).
- `zenohGatewayUrl`: Desktop's zenoh-gateway; `zenohGatewayToken`: this app's access to it, which its server connects
  with (`connect(url, { token })`). `zenohConnect`: the zenoh endpoint dimos modules are on (empty = peer on the local
  network), for a server that talks zenoh itself.
- `zenohNamespace`: Desktop's zenoh namespace, `<machineId>/<home-slug>` — this machine's id, which a rename doesn't
  change, and a slug of the Desktop home (`default` for `~/.dimos`), so a second Desktop with its own `--home` is a
  separate bus. `zenohPrefix`: `<zenohNamespace>/apps/<name>`, this install's own keys. The app's pages hear its backend
  on `<zenohPrefix>/frontend/<topic…>`: publish there directly, or
  `POST ${desktopUrl}/gateways/desktop/ui/apps/${name}/frontend/<topic…>` and Desktop publishes the body
  ([events.md](events.md)).
- `dimosDir`, `dimosPython`: the dimos checkout Desktop uses and the python dimos runs with, as the dimos gateway said
  when the app started (null when the gateway couldn't say; ask it again then).
- `recordingsDir`: the shared recordings folder, as the dimos gateway answers it. **Ask the gateway instead**
  (`GET /gateways/dimos/history/recordings`), and treat this as the offline fallback: the gateway is the only thing that
  knows, every launch is handed that same folder, and a second answer to one question is how a run launched from the UI
  once ended up writing where the Recordings app wasn't looking. dim-app's `recordingsDir()` and `watchRecordingsDir()`
  do this, the second keeping it current off the gateway's per-setting `config` event.
- `machineId`: 32 hex characters naming this machine in a fleet (Desktop 0.2.226 and newer), made once and then left
  alone, so a rename or a new network card doesn't change it. What a recording's metadata is tagged with.
- `secrets`: **the one object an app never prints.** It holds the app's secrets — its `zenohGatewayToken` among them,
  which is also still beside it for older apps. Apps print their whole `DIMOS_APP` at startup, which is exactly why
  Desktop has to redact that token out of the log it serves; a section an app skips whole is what keeps the next secret
  out of a log without Desktop having to learn its shape.
- An app reads `DIMOS_APP` and the gateways, and **never `DIMOS_HOME`**: where things are is Desktop's answer to give,
  and a path an app worked out itself is a second answer that will drift from the first.

```js
const app = JSON.parse(Deno.env.get("DIMOS_APP"))
Deno.serve({ path: app.socket }, handler)
```

It runs with the repo as its cwd and in its own process group, and its output is kept in a bounded buffer shown in the
App Store (never the service log) with its zenoh-gateway token redacted out.

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
[dim-app SDK](https://github.com/dimensionalOS/ddtk), its flake's `mkDimosApp` builds either shape:

```nix
{
    inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    inputs.dim-app.url = "github:dimensionalOS/ddtk/v0.5.0";
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

dimos's default transport is zenoh. Desktop embeds [zenoh-gateway](https://github.com/dimensionalOS/zenoh-gateway) (with
the [ROS 2 / dimos codecs](https://github.com/dimensionalOS/zenoh-dimos-codecs)), so a page can subscribe to any module's
stream (camera images arrive as H.264 video, point clouds quantized, depth lossless), publish (with a deadman for
commands), `get`, answer queries and use liveliness without a dimos-version-specific SDK. Declare
`uses: "@zenoh-gateway": <range>` in dimos.yaml and connect with the client at the commit Desktop embeds. A page reaches
the gateway at the fixed same-origin path `/zenoh-gateway`, i.e. `../../zenoh-gateway` from `/apps/<name>/`:

```js
import { connect } from "https://esm.sh/gh/dimensionalOS/zenoh-gateway@ad2bde0/client/zenoh_gateway.ts"
const zenoh = await connect(new URL("../../zenoh-gateway", location.href).href)
```

An app server gets the gateway's URL as `zenohGatewayUrl` in `DIMOS_APP` (and the zenoh endpoint as `zenohConnect`).
Topic names and encodings: zenoh-gateway's SPEC.md, and `zenoh.encodings` lists what the gateway runs.
`GET /gateways/dimos/catalog/blueprints/<name>` lists each module's streams.

What a page may do on the bus is its dimos.yaml's `zenoh:` section (above), enforced by the gateway as zenoh's own
access control: from spec v1.2 on, a file without one gets nothing, and a file at v1.1 or lower gets subscribe, publish,
`get`, queryables and liveliness on any key.

## Backend → page: events over zenoh

An app's server pushes to its pages over zenoh, never its own websocket or SSE:
`POST
${desktopUrl}/gateways/desktop/ui/apps/${name}/frontend/status` with a JSON body, and every open page of the app
subscribed to `<zenohPrefix>/frontend/**` (on its one zenoh-gateway connection) gets it. Pages ask the app's server
over plain HTTP, and get the namespace from `GET ../../gateways/desktop/management/gateways/zenoh?app=<name>`. The
keys, sizes and the snapshot + live pattern: [events.md](events.md).

## The page and the shell: insets, opening apps

An app's page runs in an iframe that fills Desktop's app layer. On a desktop-width window the shell's bottom bar (the
chat box at its left, the blueprint in its middle, the dock at its right) sits over the frame's bottom edge; the shell
posts how much as `{type: "dimos-inset", top, bottom, left, right}`, which becomes `--dim-inset-*`: keep controls above
`var(--dim-inset-bottom)`. Theme, corners and insets (apps look like Desktop in every skin, from Desktop's `/theme.css`
tokens, with no theme switch of their own): [create-apps/themes.md](create-apps/themes.md).

A page opens another app (or a built-in: `launcher`, `appstore`, `settings`) in the same window with
`parent.postMessage({dimosShell: 1, type: "open_app", app, path}, location.origin)`; `app` is the install name. From a
backend, or a page outside the shell, it's `POST /gateways/desktop/ui/apps/<name>/open` (the window the user used
last, [agent.md](agent.md)).
To open the Launcher filtered, give it a deep-link path: `{…, app: "launcher", path: "?needs=cmd_vel"}` (blueprints with
a module whose input or output name contains it, e.g. `tele_cmd_vel`; also `q=`, `robot=`, `blueprint=` to select one,
`all=1`; a link sets what it names and clears the other filters). dim-app's `openApp(id, params)` and `appInstalled(id)`
wrap this (`openApp("launcher", { query, robot, stream, selected })` puts those in the link as `q`, `robot`, `needs`,
`blueprint`). A plain link works too: `/?app=launcher&needs=cmd_vel` ([launcher.md](launcher.md)). An app opened this
way (or by `POST /gateways/desktop/ui/apps/<name>/open`) remembers what opened it: closing or minimizing it goes back
to that app if it's still open, through a chain; an app the user picks (dock, search, a card) starts fresh
(`ui/src/shell/appOpeners.ts`).

The shell draws an app's page into an image for the agent's `screenshot` and for its card when it's minimized
(`ui/src/shell/frameCapture.ts`): the page, each `<video>`'s current frame, each canvas and each same-origin iframe, as
on screen. Canvases are copied in a frame right after the page draws, so a WebGL canvas without `preserveDrawingBuffer`
comes out too, as long as the page draws within 0.4 s. A page that draws only on change (a dirty flag) draws once when
asked, or its 3D comes out empty while nothing moves: `addEventListener("dimos-capture", () => viewer.requestRender())`.

## An app in a window of its own: `app standalone`

`dimos-desktop app standalone <app>` opens an installed app as its own window, without Desktop's shell around it:
`/?view=standalone&app=<app>` frames the app's page as the shell does (same origin, its `dimosShell` messages and
`dimos-inset` still answered) and shows nothing of Desktop's but its notifications, the banners as they arrive and the
panel of them all. Nothing in the window takes a click: moving the pointer **fast** into the window's top-right corner
opens the panel, while moving there slowly is reaching for what the app has in that corner, and the click goes through.
The panel closes on Esc, a click away or the pointer leaving it. A notification's button for this app opens it here;
one for another app, the chat or a run's logs opens Desktop in the browser.

If Desktop answers on its port, it serves the window. If not, the command starts a light Desktop on that port for it:
the same routes, but only this app's server and those of the apps it `uses:`, the dimos gateway only when one of them
uses it, the zenoh-gateway unless a compatible one already answers on `zenoh_gateway.external_port`, and no boot
service, shell tool port, Launcher scan or update chores. It stops once its last window has closed (each window says
it's open every `heartbeat-s`). The window is a Chrome, Chromium, Brave or Edge app window (`--app=`, a profile of its
own per app under `~/.dimos/desktop/standalone/`), else a tab of the default browser. `--install` adds a launcher that
runs the command: `~/Applications/<title>.app` (the app's icon when `rsvg-convert` is there to draw it) or an app-menu
entry on Linux. `--no-window` prints the URL and the window's command instead of opening it.

Its settings are config.yaml's `standalone:` (`GET /gateways/desktop/settings`, read again on a `settings` event):

| Key                    | Default | What                                                                           |
| ---------------------- | ------- | ------------------------------------------------------------------------------ |
| `hot-corner-px`        | 48      | the corner's square (px)                                                       |
| `hot-corner-speed`     | 1.0     | px/ms: at least this fast into the corner opens the notifications              |
| `hot-corner-sample-ms` | 100     | the speed is over the pointer's moves in this many ms                          |
| `heartbeat-s`          | 10      | how often a window says it's open                                              |
| `idle-exit-s`          | 90      | the light Desktop stops when no window has said so for this long               |
| `closed-exit-s`        | 3       | ...or this long after its last window closed                                   |
| `browser`              | (empty) | the window's browser, a path or a command; empty: the first one found          |

## Shell commands (sudo too)

An app never runs privileged commands itself: it asks Desktop with `POST /gateways/desktop/ui/shell` (a title, a
message, and commands with a note each). Desktop shows them over the app, the user presses Run, they run in one
terminal (sudo asks once), the agent can help when one fails, and the app polls for each command's exit code and
output. dim-app's
`runShell()` does it in one call. [shell.md](shell.md).

## Apps with a Deno backend: the dim-app SDK

[dim-app](https://github.com/dimensionalOS/ddtk)'s `mkDimosApp` (above) builds a `dimos-app-server` that serves the
frontend, runs the backend module in-process and bridges the two over its own websocket; Desktop only forwards to it.

## Versions

Versions are git tags matching `vX.Y.Z` (or `X.Y.Z`). Install checks out the newest tag unless `--ref` is given; any tag
or branch can be picked from the App Store's version menu.

A tag with anything after the `X.Y.Z` core is a **beta** (`v1.1.1-beta`, `v1.1.1rc1`, `v1.1.1blah`). Install, Update and
Update all never move to a beta; it shows (labelled beta) in the version menu for testers to pick. An app on a beta
updates to the next newer stable tag (`v1.1.1` is newer than `v1.1.1-beta`), never to another beta. Order within one
core: other suffixes < `a` < `b` < `rc` < the release.
