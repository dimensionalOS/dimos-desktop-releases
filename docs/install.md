# Installing

```sh
# download the dimos-desktop binary for this machine, then:
./dimos-desktop setup
```

Or as an app in its own window (no browser tab): the macOS .app or the Linux AppImage, docs/bundle.md.

`setup` puts the binary in `~/.dimos/desktop/bin` and on PATH (a line in `~/.zshrc`, `~/.bashrc` or, on macOS bash,
`~/.bash_profile`; `--no-modify-path` skips it; a `DIMOS_HOME` other than `~/.dimos` is a scratch install that leaves
PATH and the real Desktop alone, docs/development.md), writes `~/.dimos/config.yaml`, installs the boot service (launchd
/ systemd --user, with linger), starts Desktop and opens it in the browser. It asks nothing on a fresh install (only
before replacing an installed Desktop). Without a password Desktop is this machine's only; Settings > Network access (or
`--password`, `dimos-desktop password`) lets other devices in.

**In the browser**, the installer is a checklist with the install terminal beside it, in a portal on the desktop (a
fresh setup plays its intro first: the scene draws in and the portal rises out of the floor; a click or a key skips it,
and reduced motion starts at its end). It starts in the default theme (Portal): a day after the install, one
notification says the theme can be changed and opens Settings → Appearance's theme picker (`desktop.installed_at`,
`desktop.theme_notice_sent`). Step 1, **Settings**, asks whether the Desktop service starts on boot, whether to allow
LAN access (its "whats this?" tooltip says what that means and lists this machine's addresses, `GET /api/auth` `urls`),
and the computer's password (checked with `sudo -S -v` when you press Next). Only the installer's page handles it: that
page is served from the shell tool's origin (`desktop.shell_port`), never Desktop's main port where apps run. It is
never logged or sent in an event; with LAN access on it becomes the LAN password, kept only as a salted hash
(`desktop.password_hash`; checked again with sudo first, and a later change of the computer's password doesn't follow).
Settings → Network access changes it. The installer's portal has no ✕ or –: it closes itself once everything is
installed.

**No password when sudo needs none.** Desktop asks `sudo -n -k true` once per run (`GET /api/install`'s `sudo`:
`passwordless`, `password`, `no-password`, `locked`, `not-allowed` or `missing`). With passwordless sudo (a NOPASSWD
rule: Jetsons, robots, CI) Step 1 asks for no computer password, and with LAN access on it asks for a new password for
other devices instead (kept as `desktop.password_hash`). Such a computer's logins never accept "the computer's password"
(sudo would accept any), only Desktop's own. An account that may not use sudo, or a computer without sudo, gets a note
saying so on Step 1.

**Step 1 needs sudo verified in this run.** Step 1 (Settings) is done only when its questions are answered (saved
answers come back prefilled) and sudo is usable now: NOPASSWD, a password `sudo -S -v` took this run (or one Desktop
just set), or nix is already installed (nothing needs sudo). A previous run's answers, install.json or
`first_run: false` never count. The server enforces it too: `POST /api/install/run` (every Continue, Continue (All),
retry and resume after a reload or restart) and a step-by-step `/api/install/start` answer 428 until it holds; a
password sent with them is checked with `sudo -S -v` before it's held. nix's step checks again (waiting a moment for the
page to resend the password on a retry); with no one at the keyboard (`setup --yes`, an agent) it fails at once, saying
how to go on. `GET /api/install` has `sudoNeeded` (nix isn't installed) beside `sudo` and `sudoHeld`.

**An account without a password** (a Steam Deck's `deck` out of the box: sudo refuses it until it has one). When sudo
wants a password, Desktop also reads `passwd -S` (Linux): `NP` is `no-password`, `L` is `locked`. For `no-password`,
Step 1 says "Please set a sudo password" (new + confirm); Next sends it to `POST /api/install/sudo-set-password`, which
runs `passwd` in a PTY (an empty current password where it asks, as Ubuntu does; Arch/SteamOS don't), types the new one
twice, checks it with `sudo -S -v`, and Step 1 goes on with it as its checked password. passwd's own complaints ("You
must choose a longer password") come back as the error. `locked` (only an admin can set one) gets a note with Check
again (`POST /api/install/sudo-recheck`). The shell modal's note and `setup`'s terminal hint follow the same mode.

<a id="sudo"></a>**sudo during the install** (src/install/sudo.rs): each Continue hands the password to Desktop, which
holds it in memory for that run only (zeroed when the run finishes or fails). The install shell's PATH starts with a
private folder (`<state>/sudo`, mode 0700) holding a `sudo` shim: it runs the real sudo (its absolute path, found when
the shim is written) with `-A`, and `SUDO_ASKPASS` points at `askpass` beside it, which runs `dimos-desktop askpass`:
that asks Desktop over a unix socket in the same folder (served only while the password is held, answering only this
user's processes) and prints the password for sudo. It never goes through an environment variable, an argument or a
file. A caller that picks how sudo gets its password (`-S`, `-A`, `-n`) gets the real sudo untouched, and with no
password held (the CLI, a run after a reload) the shim is plain sudo; a run that started without the password gets it
from the page when it notices. When sudo still asks in the terminal (`[sudo] password for <user>:` on Linux, `Password:`
on macOS), the page types the password at the prompt as a fallback. LAN access is applied once the install finishes (it
restarts Desktop to listen on every address); logins from other machines then check the LAN password.

Then the installer pauses before each step for **Continue** (run this step) or **Continue (All)** (run the rest without
pausing; also while a step runs). Every finished step and the current one can be clicked to see it again; the Settings
answers can be changed mid-install. An already-installed Desktop skips it. Once it's installed, **Start using dimOS**
moves the portal into the chat box's place at the bottom left and the rest of the Desktop appears around it. The CLI
(`setup`, `terminal retry` / `terminal start`, `POST /api/install/start`) runs every step straight through.

**Over SSH** (`SSH_CONNECTION`, `SSH_CLIENT` or `SSH_TTY`; inside tmux, the attached client's, from
`tmux
show-environment`) there's no browser to open on this machine, so setup:

- in **VS Code's Remote-SSH terminal** opens the page on the computer you're at through VS Code: its `$BROWSER`
  (`…/bin/helpers/browser.sh`) sends `openExternal` over `VSCODE_IPC_HOOK_CLI`, and VS Code forwards a localhost URL's
  port before opening it. Only when the hook answers (a tmux pane can outlive the VS Code window that set it). VS Code
  forwards Desktop's port; its terminal's port (+1) needs forwarding too if VS Code didn't pick it up by itself.
- otherwise prints three ways to finish: an SSH tunnel to run on the computer you're at, built from `SSH_CONNECTION` and
  `$USER` (`ssh -N -L 5555:127.0.0.1:5555 -L 5556:127.0.0.1:5556 user@host`, `-p` for another SSH port: Desktop's port
  and its terminal's) then `http://localhost:5555`; the LAN / tailnet URLs when network access is on; and
  `dimos-desktop terminal start && dimos-desktop terminal attach` to run the install in that terminal, sudo prompt and
  all. URLs are terminal links (OSC 8) when stdout is a terminal.

Headless Linux (no `DISPLAY` / `WAYLAND_DISPLAY`) gets the same three ways.

| step          | what                                                                                                                                                                                 |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Agentic setup | the newest dimcode that suits this Desktop, installed, and its gateway started: first, so it can fix a later step that fails (from the GUI it stops here on a failure)               |
| Nix           | nix (nixos.org's multi-user installer, so a sudo prompt), and the dimOS binary cache trusted                                                                                         |
| System apps   | right after nix: the catalog's `system: true` apps (Recordings, Controller, Map Editor; the default dock), in parallel, through the App Store's install; one that fails is a warning |
| dimOS         | the newest dimos that suits this Desktop _and_ that dimcode, installed, its dimos gateway started, checked                                                                           |

Every command runs in **the install terminal**: one shell on the server (the shell session `install`,
[shell.md](shell.md)), so sudo asks for the password once. The GUI shows it beside the checklist (it opens by itself
while installing, after a failure, and on a machine that is missing something; `/#install` opens it), and the CLI and
agents use the same one (agents also through the MCP tools `shell_read` / `shell_type`):

```sh
dimos-desktop terminal attach     # this terminal becomes the install terminal (typing too); Ctrl-] detaches
dimos-desktop terminal status     # the checklist; after a failure the error and a prompt for a debugging agent
dimos-desktop terminal wait       # new output until it ends (exit 0 done, 1 failed) or goes quiet (3: a prompt?)
dimos-desktop terminal read       # output since the last read (--all: everything kept)
dimos-desktop terminal send 'y'   # type into it: the running command, or the shell after a failure (Enter added)
dimos-desktop terminal retry      # run the install (again; also `terminal start`): what's done is skipped
```

The install keeps going if the browser, the SSH session or `setup` goes away; its state is in
`~/.dimos/desktop/install.json` and its whole output (Desktop's lines, nix's, dimcode's, dimos's and uv's: everything
the install terminal shows) in `~/.dimos/desktop/logs/install.log`. Each run appends to it; past 20 MB it's moved aside
to `install.<time>.log` when Desktop starts, never overwritten.

## An agent running setup

`setup` returns once Desktop is up, with or without a terminal (an agent running `curl … install.sh | bash` gets its
prompt back): the user finishes in the browser (Settings with the password, then Continue per step), and setup prints
how to follow along from where it ran:

```
Finish setup in the browser: http://127.0.0.1:5555
Follow the install from here:  dimos-desktop install logs --follow
Wait for it to finish:          dimos-desktop install status --wait   (exit 0 done, 1 failed, 3 waiting for the user)
Full log: ~/.dimos/desktop/logs/install.log
Agents: read http://127.0.0.1:5555/llms.txt
```

`install logs` prints the install terminal's output as plain text (`--raw` keeps colors); `--follow` keeps printing
until the install finishes or fails, waiting if the user hasn't started it, and says on stderr when it's waiting for the
user. `install status` prints where it is (`running: Nix (Install nix)`,
`waiting for the user: Settings (Step 1) in
the browser…`, `done`, `failed: …`) and the checklist; `--wait` blocks until
done (0), failed (1) or waiting for the user (3: tell them what's asked, then run it again); `--json` for scripts.
Neither prints a password: sudo is answered by Desktop (install/sudo.rs) and the terminal never echoes it.

With `--yes` (or `DIMOS_YES=1`, for CI) `setup` runs the install itself instead: no browser, the defaults for the
first-run question (start on boot), localhost only unless given `--password`, `NON_INTERACTIVE=1` for the install
commands; it prints how to drive the install terminal and where every log is, then runs `terminal wait`. A sudo prompt
still needs a person: `terminal send` refuses at a password prompt, so the password never passes through an agent.

When a step fails, the checklist shows why under it, with **Copy logs and recommended next steps** (`status.help`, also
`terminal status`: the failure, the end of that step's output, the log and config paths, and how to drive the installer)
and **Ask for help in Discord**. Once Desktop's agent can answer (dimcode running with a model and its key: `ready` in
`GET /api/agent`, from dimcode's `GET /api/ready`), **Fix it with the agent** hands it that prompt: it works in the
install terminal with the `shell_read` / `shell_type` tools (each call shows under the step), and `shell_resolve` retry
on `install` retries the step. With the agent running but no key yet, the step offers to add one.

## Versions: `dimos.yaml`

dimcode and dimos each have a `dimos.yaml` at their repo root; Desktop's own is at the root of this repo. Desktop
installs **tags**, never a branch head: its `dimos.yaml` `tags:` names a prefix and a version range per component, and
the installer takes the newest `<prefix><version>` tag in that range that every side accepts. Tags don't move, so a push
to dimos's or dimcode's branches can't change what a released Desktop installs.

| component | tags                                                   | the version is                                                                  |
| --------- | ------------------------------------------------------ | ------------------------------------------------------------------------------- |
| dimos     | `desktop-gateway-v<x.y.z>` on dimensionalOS/dimos      | the gateway API's (`api: version` in its dimos.yaml); the patch counts releases |
| dimcode   | `desktop-agent-v<x.y.z>` releases on the binary mirror | its agent contract's                                                            |

- The tag list comes over git's own HTTP protocol (one `ls-refs` request to `https://github.com/<repo>.git`: no git CLI,
  no API rate limit) and is remembered in `~/.dimos/desktop/cache/`, which answers when GitHub can't be reached.
- A version with any suffix (`1.18.0-rc1`, `1.18.0beta`, `.post1`) is a beta: never picked by itself.
- In-range tags are read newest first (dimos: its `dimos.yaml` at the tag; dimcode: the release's
  `<releases>/download/<tag>/dimos.yaml`) until one fits; a newer one that doesn't is a warning saying why.
- No tag in range, or none that fits: the install fails with "no <component> release works with this Desktop … Update
  dimOS Desktop (Settings → Updates, or `dimos-desktop update`)".
- The install log shows each step (`→ picked desktop-gateway-v1.19.0 (0.0.14, 3f4f046dcb)`); Settings shows the
  installed tag and commit under dimos ("installed tag") and Services ("agent tag"); `GET /api/info` has them in
  `components`.
- Developers: `dimos-desktop install --dimos-ref <tag, branch or commit>` / `--dimcode-ref <…>` (dimcode's private
  source repo, built from source) installs exactly that ref, still checked for compatibility.

### Shipping a dimos or dimcode change to Desktop users

Tag it; widen Desktop's range only for a contract change.

- dimos: `git tag -a desktop-gateway-v<x.y.z> <commit> -m … && git push origin refs/tags/desktop-gateway-v<x.y.z>` (push
  only that tag). Same gateway API: bump the patch. An additive API change (minor bump of `api: version`): a new minor,
  which Desktops already in the field take too. A breaking change: a new major, then release a Desktop whose range takes
  it.
- dimcode: push the tag `desktop-agent-v<x.y.z>` to dimensionalOS/dimcode (its release workflow builds the binaries; a
  suffixed tag is a prerelease), then `scripts/mirror-release.sh desktop-agent-v<x.y.z>` copies the release to the
  public mirror Desktop reads. Breaking the contract before 1.0 is a new minor.
- Never move or delete a tag: released Desktops resolve them.

```yaml
name: dimcode # dimos-desktop | dimcode | dimos
version: "0.1.0" # 1.2.3, v1.2.3, 0.0.14b1, 0.1.0rc2, 0.0.13.post1
requires: # ranges on the others: ">=0.2 <0.3"
    dimos-desktop: ">=0.2 <0.3"
source: tarball # Desktop downloads and unpacks this ref for `install` (omit: no source needed)
install: | # bash, in the install terminal. cwd = the unpacked source. env: PREFIX, SRC, REF, COMMIT, DIMOS_HOME,
    ...      # NON_INTERACTIVE (dimos: DIMOS_DIR instead of PREFIX); re-runnable
start: | # bash: start the service and return once it's started (Desktop runs it whenever it needs the service)
    ...
socket: | # bash: print the unix socket the service answers HTTP on (`GET /healthz` → 200)
    ...
```

A tag fits when Desktop's `requires.<name>` accepts its `dimos.yaml` version and its `requires.dimos-desktop` accepts
Desktop's; dimos must also fit the chosen dimcode both ways. What was installed, from which tag (and commit) and with
which `dimos.yaml`, is recorded in `~/.dimos/desktop/components/<name>.json`: Desktop starts the agent with those
`start:` / `socket:` commands from then on, in its install directory (`$PREFIX`). The dimos gateway's come from the
dimos.yaml of the checkout in `dimos.dir` itself and run in that checkout (see below); the record is only used for a
checkout that has no dimos.yaml.

- **dimcode**: Desktop installs the picked release's prebuilt binary (default releases
  `https://github.com/jeff-hykin/dimcode-mirror/releases`, a public mirror of the private repo's releases;
  `DIMOS_DESKTOP_DIMCODE_RELEASES` = another base URL or `owner/name`). Its `binaries:` names the gzipped binary for
  each `<os>-<arch>` and a `SHA256SUMS`: Desktop downloads `<releases>/download/<tag>/<asset>` with no GitHub
  credentials, checks it, unpacks it to `$PREFIX/bin/dimcode` and runs its `--version`. When there's none for this
  machine or any of that fails, `install` builds `binaries.commit` from source instead: it builds `$PREFIX/bin/dimcode`
  (bun is downloaded into `$PREFIX` if missing: no node, nix or git needed), into `~/.dimos/dimcode/<version>`. The
  item's detail says which it was. `start` gets `DESKTOP_MCP_URL`, `DESKTOP_PROMPT_FILE`, `DESKTOP_WORKSPACE`
  (docs/agent.md).
- **dimos**: `install` runs dimos's `scripts/install.sh` for that ref into `dimos.dir` (default `~/.dimos/dimos`). A
  dimos already there is kept when its version fits. `start` gets `DESKTOP_BIN`, `DIMOS_DIR`, `DIMOS_SERVER_SOCKET`,
  `DIMOS_ZENOH_NAMESPACE` (Desktop's `<ns>`, docs/events.md), `ZENOH_CONNECT` (`zenoh_gateway.connect`) and
  `DIMOS_RECORDINGS_DIR` (Desktop's recordings folder, the one its apps get).

## Updating

Desktop updates itself from the same releases install.sh downloads (`DIMOS_DESKTOP_REPO`, default
dimensionalOS/dimos-desktop-releases; the asset `dimos-desktop-<arch>-<os>`): Settings → Updates, a notification when a newer
release is out (checked a minute after start and every 6 hours; `DESKTOP_NO_UPDATE_CHECK=1` turns it off), or
`dimos-desktop update [--check] [--yes] [--rollback]` (`update <app>` still updates an app). Only the boot service's
installed binary (`~/.dimos/desktop/bin/dimos-desktop`) updates itself; config and apps are left alone.

1. The release's binary is downloaded to `bin/dimos-desktop.new` and checked: its size and SHA-256 (GitHub's asset
   digest, else the release's `SHA256SUMS`), then `--version` must say the release's version.
2. The live binary is copied to `bin/dimos-desktop.prev` and the new one renamed over it (the live path always holds a
   whole binary), and `desktop/update.json` records the probation: from, to and a deadline (absolute, so it survives
   restarts).
3. A watchdog, `dimos-desktop update-watch` run from `.prev` (the old binary, detached from the service), starts; then
   Desktop exits and the boot service starts the new binary.
4. The page that asked shows "Updating…" and polls `GET /api/desktop/update`; it reloads only once the new version
   answers there and the watchdog has seen it healthy. The new page asks "Keep dimOS Desktop <new>?" with a countdown
   (`DESKTOP_UPDATE_CONFIRM_SECS`, 60). Keep (`POST /api/desktop/update/keep`) ends probation.
5. Revert, or no Keep by the deadline, or no healthy answer within `DESKTOP_UPDATE_HEALTH_SECS` (120) of the restart (a
   binary that crashes at startup): `.prev` and the live binary trade places and the service restarts into the old one,
   which shows a notice saying why. The watchdog does this for a timeout; if it died too, the new Desktop does it itself
   past the deadline, and any Desktop starting during an expired probation rolls back first.

`.prev` stays after a Keep: Settings' "Roll back to the previous version" or `dimos-desktop update --rollback` swaps
back any time. A release's `SHA256SUMS` is published by `.github/workflows/release.yml`.

An existing dimos checkout in `dimos.dir` is fetched against the picked ref; when it's behind, the install offers
"Update dimOS (behind by N commits)", yes by default: a checkbox in the GUI, a y/N in an attended
`dimos-desktop terminal wait`, taken with `setup --yes` (`POST /api/install/answer` answers `status.question`). Yes
checks out the picked tag detached (a branch that was checked out keeps its commits) and runs dimos's install command on
it, which re-syncs the venv. A checkout with uncommitted changes, or detached commits of its own, is left alone with a
warning.

## Uninstalling

```sh
dimos-desktop uninstall                       # asks: Uninstall everything (dimos + desktop + dimcode)?
dimos-desktop uninstall --desktop-only --yes  # no questions: Desktop only
dimos-desktop uninstall --all --yes           # no questions: everything
```

It lists what it removes, then does it. Desktop only (the prompt's "no"): the boot service, the running Desktop and its
apps' servers, `~/.dimos/desktop` (the binary, sockets, logs, downloaded tools, install records), installed apps
(`~/.dimos/apps`), `config.yaml` and the `# dimos-desktop` PATH line setup added to `.zshrc`, `.bash_profile` or
`.bashrc`. Everything (the prompt's "yes", `--all`) also stops and removes dimcode (`~/.dimos/dimcode`, and a scratch
home's dimcode home, socket and state) and the dimos Desktop installed, only when its install record says Desktop put it
there and it is inside `~/.dimos`: a `dimos.dir` of your own is kept. Your recordings and `~/.dimos/data` (apps' data)
are kept unless `--purge-data`. Without a terminal it needs `--all` or `--desktop-only`. `DIMOS_HOME` is respected.

## The dimos gateway

`/dimos/` (docs/api.md) is served by dimos's own gateway (dimos/gateway/, in Python), its own process on a unix socket,
which Desktop proxies and starts on demand with the `start:` (and `socket:`) of the dimos.yaml in the checkout at
`dimos.dir`. Desktop runs no dimos code of its own and reads nothing of the checkout but that dimos.yaml: everything
else it shows about dimos (its version, blueprints, robots, runs, config, the python it runs with) is the gateway's
answer. A checkout whose dimos.yaml has no `start:` (a dimos older than the gateway) can't be driven: `/dimos/*`
answers 503, and Settings, `GET /api/info` (`dimosServer.error`, `dimos.error`) and Desktop's log say why. Desktop
restarts the gateway when `dimos.dir` changes (Settings → dimos → Change…, `PUT /api/dimos-dir`: the old checkout's
gateway is stopped first, and the Launcher's catalog, robots.json, blueprint lists and app servers are redone for the
new one), when the checkout's dimos.yaml is newer than the gateway (a pull, a checkout of another tag), and on
`POST /api/dimos-server/restart` (Settings' Restart). The gateway publishes its events on zenoh itself, under the
namespace Desktop starts it with (`DIMOS_ZENOH_NAMESPACE`); Desktop hears them there too (docs/events.md).

## Binary caches

`install.binary_caches` (default: `https://dimensionalos.cachix.org` for dimos, `https://dimos-desktop.cachix.org` for
apps) are added to `/etc/nix/nix.conf` (`/etc/nix/nix.custom.conf` under Determinate Nix) as `extra-substituters` /
`extra-trusted-substituters` / `extra-trusted-public-keys` (sudo; the nix daemon is restarted), so app and dimos builds
download what CI built. nix ignores substituters a non-trusted user passes on the command line, hence nix.conf. The user
is **not** made a nix trusted user (that is root-equivalent): only these caches are trusted. A cache already in nix.conf
(url and key) is left alone. When adding fails the install carries on with a warning: apps then build from source. On
NixOS (read-only nix.conf) the step says which `nix.settings` lines to add instead.

An app's own `caches:` (dimos.yaml) aren't trusted by the installer. Installing such an app passes the ones nix.conf
already trusts (and all of them for a user an older Desktop made a nix trusted user); for the rest the job says so and
gives the one command that trusts just those caches (`extra-trusted-substituters` + `extra-trusted-public-keys`), and
the app builds from source. The App Store's "Run it" runs that command through [shell.md](shell.md) (the user presses
Run and types the sudo password in the terminal). [app-store.md](app-store.md) has the API.

## Config (`install:` in `~/.dimos/config.yaml`)

```yaml
install:
    dimcode: { repo: dimensionalOS/dimcode } # its source, for --dimcode-ref and source builds
    dimos: { repo: dimensionalOS/dimos } # its desktop-gateway-v* tags
    binary_caches:
        - {
              url: https://dimensionalos.cachix.org,
              key: "dimensionalos.cachix.org-1:20ynj6TjpoD3qTxkdNoeHtgs2G2pNvgAq1EQYLTHJXI=",
          }
```

Environment overrides (tests, unusual machines; setup passes `DESKTOP_*` on to the service): `DESKTOP_NIX_INSTALL` (the
script that installs nix), `DESKTOP_FORCE_NIX_INSTALL` (run it even when nix is there), `DESKTOP_GITHUB_API` /
`DESKTOP_GITHUB_RAW` / `DESKTOP_GITHUB_WEB` (where GitHub is), `DIMOS_DESKTOP_PASSWORD` (setup's password: network
access on).

Settings → Installer → Replay installer resets the checklist to step one and opens a fresh installer page. Saved
settings stay prefilled; components already installed are reused. `POST /api/install/replay` clears the completed
checklist and any held sudo password, without starting commands. It returns 409 while an installer is running or
paused, or its terminal still has a command running. The next Continue follows the normal setup flow.

### App icon

The CLI installer also creates an app icon. On macOS, open **dimOS Desktop** in `~/Applications` (drag it to the Dock to keep it there). On Linux, find **dimOS Desktop** in your application menu; an existing Desktop folder also gets a shortcut. Some Linux desktops ask you to trust a new desktop shortcut once.

This launcher opens Desktop in your default browser and starts its service if needed. It does not require the optional Mac bundle or AppImage. An existing Mac native app is preserved. Scratch installs using a custom `DIMOS_HOME` leave your app menu alone. Uninstalling Desktop removes the launcher.
