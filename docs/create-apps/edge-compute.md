# Changing an app that runs on a robot

A robot's computer (a Jetson, a Raspberry Pi) is slow to build on. A `nix build .#dimosApp` that takes a minute on a
laptop can take tens of minutes there, mostly compiling dependencies a laptop already has. So **build on your own
machine, copy the result over, and have Desktop run it.** Never `nix build`, `cargo build`, `deno install` or
`npm install` on the robot to try a change.

The loop:

1. Edit the app in a checkout on your laptop.
2. Build only what changed (the page, the server, or both) for the robot's CPU, as a debug build.
3. `rsync` it to the robot.
4. Point the robot's installed app at it and have Desktop reload it.

When you're done, release it (push and tag). CI builds the real thing for every machine type, and the robot downloads
that instead of building it (below, [How a robot normally gets an app](#how-a-robot-normally-gets-an-app)).

Below, `ROBOT` is the robot's ssh name (`ssh ROBOT` works) and `APP` the app's name (`dimos-desktop list` on the robot
names them). `ssh ROBOT uname -m` gives its CPU: `aarch64` for a Jetson or a Pi 4/5, `x86_64` for a NUC.

## The page (frontend)

A page is HTML, JS and CSS: the same files on every machine, so there's nothing to cross compile. Build it on your
laptop the way the app's flake does (usually `deno task build` or `npx vite build` in `frontend/`) and copy the output.

- **A static app** (no `flake.nix`) is served straight from `~/.dimos/apps/APP/frontend/` on the robot, re-read per
  request:

  ```sh
  rsync -a --delete frontend/ ROBOT:.dimos/apps/APP/frontend/
  ```

  Reload the page. Done.

- **A built app** serves the page its build made, from the folder its wrapper exports (`MAP_BUILDER_FRONTEND=...`,
  `CONTROLLER_FRONTEND=...`). Copy the built page next to the install,
  `rsync -a --delete frontend/dist/ ROBOT:.dimos/apps/APP/hot/frontend/`, and in `hot/bin/dimos-app-server` (next
  section) point that export at `$HOME/.dimos/apps/APP/hot/frontend`. An app that reads its page from disk per request
  (dim-controller does, `CONTROLLER_FRONTEND`) needs only this rsync and a page reload after the first time; its
  `scripts/hot` does all of this on the machine it runs on.

## The server (Rust): cross compile a debug build

Rust cross compiles from a Mac or a Linux laptop with [cargo-zigbuild](https://github.com/rust-cross/cargo-zigbuild):
zig is the linker, so there's no Linux machine or cross gcc involved. Build a **static musl** binary: it runs on any
Linux of that CPU, whatever its glibc, so it doesn't matter how old the robot's Ubuntu is.

One-time setup:

```sh
rustup target add aarch64-unknown-linux-musl x86_64-unknown-linux-musl
cargo install --locked cargo-zigbuild   # and zig: `brew install zig` or `nix profile install nixpkgs#zig`
```

Then, in the app's checkout (its Cargo workspace; `-p` picks the server's package):

```sh
export CARGO_PROFILE_DEV_DEBUG=0   # no debug info: dim-controller's server is 28 MB instead of 272 MB, which matters over wifi
cargo zigbuild -p dimos-app-server --target aarch64-unknown-linux-musl            # debug: the one to iterate on
cargo zigbuild -p dimos-app-server --target aarch64-unknown-linux-musl --release  # release: slower to build, what CI ships
```

The binary is `target/aarch64-unknown-linux-musl/debug/dimos-app-server`. The first build compiles every dependency
(dim-controller's server: about 2 minutes on an M-series Mac; dim-map-builder's, which optimizes its dependencies even
in debug, 7); after that, a change to the app's own code rebuilds one crate (3 seconds for dim-controller's).

**Debug builds are for iterating.** They skip the optimizer, so they build several times faster, and they're fine for a
server that answers HTTP and moves messages around. Use `--release` when the server does heavy per-frame work (point
clouds, video, encoding) and a debug build can't keep up, or when measuring speed. A middle ground, in `Cargo.toml`, is
optimizing the dependencies but not the app's own crate:

```toml
[profile.dev.package."*"]
opt-level = 2
```

The app's `flake.nix` usually has the same build already, as `.#dimosApp-aarch64-linux` (a release build, wrapped with
its page). `nix build .#dimosApp-aarch64-linux` from a Mac makes exactly what CI ships; slower than `cargo zigbuild` per
change, but the one to check before a release.

## The server (Deno, Bun, Python)

Nothing to compile: the server is source or one bundled `.js` file, run by the robot's own `deno`. Build the bundle on
your laptop the way the flake does (often `deno bundle ... -o server.js backend/main.ts`) and rsync it. Don't run
`deno install`, `npm install` or `uv sync` on the robot to try a change; a dependency change is a release (CI makes the
robot's build), not a hot load.

## Copy it and run it (hot loading)

Desktop runs `~/.dimos/apps/APP/result/bin/dimos-app-server`, with `DIMOS_APP` set. `result` is a symlink (to the nix
build); point it at your own folder instead and ask Desktop to reload the app:

```sh
# every time: copy the build
ssh ROBOT mkdir -p .dimos/apps/APP/hot/bin
rsync -a target/aarch64-unknown-linux-musl/debug/dimos-app-server ROBOT:.dimos/apps/APP/hot/bin/server

# the first time only: keep the nix build (to go back to), and make hot/'s wrapper from the nix one (the same exports,
# e.g. where its page is, but it runs hot/bin/server)
ssh ROBOT 'cd .dimos/apps/APP && ln -sfn "$(readlink result)" .result-nix &&
    sed "s|^exec .*/bin/dimos-app-server|exec \"\$(dirname \"\$0\")/server\"|" .result-nix/bin/dimos-app-server > hot/bin/dimos-app-server &&
    chmod +x hot/bin/dimos-app-server && ln -sfn "$PWD/hot" result'

# every time: restart it
ssh ROBOT curl -fsS -X POST localhost:5555/gateways/desktop/management/apps/APP/reload
```

From then on, an iteration is the build, the `rsync`, and the reload: seconds, not a robot-side build (dim-map-builder's
25 MB debug server reached a Jetson over wifi in 8 seconds). The server's output is in the App Store, on the app's page.

**Back to the release:**
`ssh ROBOT 'cd .dimos/apps/APP && ln -sfn "$(readlink .result-nix)" result && rm -r .result-nix hot'` and reload, or
`ssh ROBOT 'bash -lc "dimos-desktop checkout APP <tag>"'` (`dimos-desktop` is in `~/.local/bin`, which a plain
`ssh ROBOT cmd` doesn't have on its PATH). A Desktop update or `dimos-desktop checkout` of the app replaces `result`,
which also ends the hot load.

If your change touches `dimos.yaml` (a new `uses:` call or `provides:` route), rsync it too
(`rsync dimos.yaml ROBOT:.dimos/apps/APP/`): Desktop refuses calls the installed one doesn't list.

**Why not `nix copy`?** `nix copy --to ssh://ROBOT ./result` sends a local nix build, but the robot only takes it when
the ssh user is one of its nix `trusted-users` (usually only root) or the build is signed. CI's builds are signed (the
cachix cache), so the robot downloads those itself; your local ones go over rsync.

## How a robot normally gets an app

Installing or updating an app on a robot shouldn't build anything either. Each app's CI (on a Mac runner) builds
`.#dimosApp-aarch64-linux` and `.#dimosApp-x86_64-linux` and pushes them to the `dimos-desktop.cachix.org` binary cache,
and the app's `dimos.yaml` says where to find them:

```yaml
nix:
  cache:
    aarch64-linux:
      - packages.aarch64-darwin.dimosApp-aarch64-linux
```

Desktop on the robot tries those first, download only (`--max-jobs 0`, a miss fails in seconds), and builds `dimosApp`
itself only when none is there ([apps.md](../apps.md), `nix:`). So: when a robot starts building an app during an
install, the cache doesn't have that commit (CI didn't run, failed, or had no `CACHIX_AUTH_TOKEN`). Fix CI rather than
wait out the build. A new app gets these outputs by copying an example's flake (`crossServer` / `linuxApp` in
dim-controller's).
