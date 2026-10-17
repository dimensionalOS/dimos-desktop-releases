# Development

```sh
deno task ui:build   # build the React UI into ui/dist (the binary embeds it)
cargo run -- serve --no-service    # the server on :5555 without registering the boot service
deno task ui:dev     # the UI with hot reload, forwarding /api, /dimos, /apps, /zenoh-gateway to :5555 (DESKTOP_API to change)
cargo test           # unit tests (non-UI only), incl. the /dimos/ JSON shapes against a fake dimos checkout
deno task ui:check   # type-check the UI
deno task build      # ui:build + cargo build --release → target/release/dimos-desktop (one file)
```

Set `DIMOS_HOME=/some/dir` to keep a development or test instance out of `~/.dimos`. Such a scratch home sits beside the
real one on its own: its boot service gets its own name (`org.dimensional.dimos-desktop-<dir>-<hash>`), dimcode's home
and socket and dimos's run registry live under it (`DIMCODE_HOME`, `XDG_STATE_HOME`), `setup` takes a free port and
leaves your shell's PATH alone (`--modify-path` to change it). Each variable set explicitly (`DIMOS_DESKTOP_SERVICE`,
`DIMCODE_HOME`, `XDG_STATE_HOME`, `--port`) wins. `dimos-desktop uninstall --all --yes` removes it again (its dimcode
gateway and dimos gateway stopped).

## Hot-patching the UI

The binary carries the UI, but serves it from disk, re-read on every request: a UI-only fix is an rsync, not a rebuild.
Under `<DIMOS_HOME>/desktop/ui/`:

- `<hash>/` is the built-in UI, written there at start (the hash is of the embedded files). It is managed: missing or
  edited files are put back on the next start, and an older build's `<hash>/` is removed. Don't patch it.
- `override/` wins while it has an `index.html`, as does `DIMOS_DESKTOP_UI=<dir>` (before `override/`). Emptying or
  removing it brings the built-in UI back, no restart. Settings' "desktop version" line says "hot-patched UI" while one
  is served, and `GET /api/info` has `ui: { source: embedded | override | env, dir, embedded }`.

```sh
run/ui_patch --host nvidia@r1-pro-0219   # deno task ui:build, rsync ui/dist → the robot's override/, reload its pages
run/ui_patch                             # the same, for this machine's Desktop
run/ui_patch --dist some/dist            # push a build you already have
run/ui_patch --clear --host nvidia@r1-pro-0219   # back to the built-in UI
```

`POST /api/desktop/ui/reload` (what `run/ui_patch` calls, on the target's 127.0.0.1) reloads every open Desktop page.
The next Desktop release or rebuild doesn't remove an override: clear it once the fix has shipped.

## Layout

| Path                   | What                                                                                              |
| ---------------------- | ------------------------------------------------------------------------------------------------- |
| `install.sh`           | what the README's one-liner runs: downloads this machine's binary, runs `dimos-desktop setup`     |
| `src/main.rs`          | the CLI: `setup`, `uninstall`, `status`, `serve`, `service`, app `install`/`update`/…, `dimos …`  |
| `src/setup.rs`         | installing Desktop itself, then dimos with dimos's own `scripts/install.sh`                       |
| `src/service.rs`       | the boot service (launchd, systemd --user), re-checked on every `serve`                           |
| `src/server/`          | the HTTP server: `/api` (Desktop), `/dimos` (tooling), `/apps` and the UI's files                 |
| `src/dimos/`           | starting dimos's gateway (its dimos.yaml `start:`) and talking to it on its unix socket            |
| `src/apps/`            | installing apps (git + `nix build .#dimosApp`), the catalog, running their `dimos-app-server`s    |
| `src/shell/`           | shell commands run for apps and the installer, each session in one PTY (docs/shell.md)            |
| `src/zenoh_gateway.rs` | the embedded zenoh-gateway apps use to reach dimos modules, served at `/zenoh-gateway`            |
| `ui/`                  | the React + Vite UI, embedded into the binary                                                     |
| `.github/`             | CI: checks, native builds of all four targets, installing on every GitHub runner; release on `v*` |

## How Desktop drives dimos

Only through dimos's gateway ([api.md](api.md), the `/dimos/` API): Desktop runs no Python and reads nothing of the
checkout but its `dimos.yaml`, the install contract ([install.md](install.md)):

- `install:` installs dimos (dimos's own `scripts/install.sh`), `start:` starts the gateway and `socket:` says where it
  listens. Everything else (blueprints, the catalog, robots.json, runs and launches, logs, config, uploads, the python
  dimos runs with) is the gateway's answer.
- The gateway's events come over zenoh (`<ns>/dimos/events/<type>`, [events.md](events.md)).

## Releasing

Bump `version` in `Cargo.toml`, commit, then tag `v<version>` and push the tag. The release workflow builds all four
binaries and attaches them and `install.sh` to a GitHub release in the private dimensionalOS/dimos-desktop, then copies it to this public mirror
(jeff-hykin/dimos-desktop-mirror: releases and install.sh only, no source), which install.sh and the self-updater
download from: once the binaries and arm bundles are out, again for the Intel Mac ones (`DESKTOP_MIRROR_TOKEN`, a
fine-grained token with Contents write on the mirror). By hand: `scripts/mirror-release.sh v<version>`.

dimos and dimcode aren't part of a Desktop release: Desktop installs their newest tag in its `dimos.yaml` `tags:`
ranges. To ship a dimos or dimcode change to Desktop users, tag it (`desktop-gateway-v<x.y.z>` /
`desktop-agent-v<x.y.z>`, [install.md](install.md#shipping-a-dimos-or-dimcode-change-to-desktop-users)); bump Desktop's
range only for a contract change, in the Desktop release that speaks the new contract.
