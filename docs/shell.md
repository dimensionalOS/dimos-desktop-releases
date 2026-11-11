# Shell commands: `POST /api/desktop/shell`

Any app (or Desktop's own pages) can run shell commands, sudo ones included, through Desktop. The app sends a list of
commands, each with a note for the user; Desktop shows them in a modal over the app and nothing runs until the user
presses **Run**. They run one after another in **one shell** (one PTY), so a sudo password typed once covers the rest.
The app long-polls for the result. When a command fails, the session stops there: the user, or Desktop's agent, fixes
the cause in that same shell, then retries the command, marks it done or skips it.

The installer, the App Store's "trust the binary caches" command and Settings' shell all use it.

## Asking

```http
POST /api/desktop/shell
{
  "title": "Fix LAN discovery",                       // what it's for, shown to the user
  "message": "A VPN took the route the Go2 probe needs.",  // optional, more words
  "app": "dim-go2-dash",                              // optional: default is the asking page's (its Referer)
  "commands": [
    { "run": "sudo route -n add -host 231.1.1.1 -interface en0", "note": "Send the probe over Wi-Fi" },
    { "run": "route -n get 231.1.1.1", "note": "Check the route", "needsStdout": true }
  ],
  "timeout": 600                                      // seconds to wait for Run (default 600)
}
→ { "id": "sh-1791000000-1", "status": "pending", "session": {...} }
```

`run` is bash, run in the home folder (`cwd` and `env: {NAME: value}` change that). `needsStdout`: the caller wants the
command's stdout (and stderr) apart from the terminal's text. Desktop then pipes them through `tee` into files, so the
command sees pipes there instead of the terminal (no progress bars or colors; a prompt still works, sudo asks on the
terminal itself). Other commands write straight to the terminal and come back as `output`, what the terminal showed.

Then poll until it finishes (the answer holds up to `wait` seconds, at most 120):

```http
GET /api/desktop/shell/<id>?wait=60
→ { id, app, title, message, status, reason, current, help, prompt, busy, createdAt, finishedAt,
    commands: [{ run, note, needsStdout, status, exitCode, output, stdout, stderr, attempts, resolvedBy }] }
```

| `status`    | meaning                                                                                       |
| ----------- | --------------------------------------------------------------------------------------------- |
| `pending`   | shown, waiting for the user to press Run (a banner and notification say an app is asking)     |
| `running`   | a command is running                                                                          |
| `blocked`   | a command failed; waiting for a fix and retry / done / skip (`help` is a prompt for an agent) |
| `succeeded` | every command is done or skipped (`resolvedBy` says who marked one instead of it succeeding)  |
| `failed`    | the user gave up after a failure (`reason`)                                                   |
| `cancelled` | cancelled before or while running, or nobody pressed Run within `timeout` (`reason`)          |

A command's `status` is `pending`, `running`, `done`, `failed` or `skipped`; `exitCode` is 128 + the signal when one
killed it, 130 when it was interrupted with Ctrl-C. The caller may `POST /api/desktop/shell/<id>/cancel` itself.

The dim-app SDK wraps all of this: `runShell({ title, message, commands })` resolves to the finished session
([dim-app](https://github.com/dimensionalOS/ddtk)'s `shell.js`).

## What the user sees

The modal sits over the asking app's frame (the shell lays a transparent `/?view=shell&id=<id>` page over it). One
command: the message, the command and, after Run, the terminal. Several: a checklist beside the terminal, as the
installer's. A window showing another app gets a card ("Go2 Ctrl wants to run 2 commands", Show); a request from no app
(or an unknown one) covers the whole window. Buttons: Run / Cancel; while running Cancel; when blocked Retry, Mark done
(not for a `needsStdout` command: its caller needs its real output, so it must run again), Skip, Ask the agent to fix
it, Give up; at the end Close (a success closes by itself). With no Desktop window open nobody can press Run: the
request waits for `timeout`, then is `cancelled`.

## Fixing a failure: the agent

Between commands the shell is an ordinary interactive bash, so the user (in the terminal) or the agent can type into it.
The agent has three MCP tools ([agent.md](agent.md)): `shell_read` (the session, its `help`, and the terminal's text),
`shell_type` (an answer to a prompt, or fix commands at the shell's prompt; Ctrl-C), and `shell_resolve` (`retry`,
`done`, `skip`). The agent never types a password: `shell_type` (and `POST …/input`) is refused while the terminal asks
for one, and the agent tells the user to type it. A password typed into the terminal isn't echoed, so it never appears
in what the agent reads.

## The other endpoints

| Route                                 | Body / query                       | What                                                                                                                              |
| ------------------------------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `GET /api/desktop/shell`              |                                    | `{ sessions }`: every session kept (finished ones for 30 min), no output                                                          |
| `GET /api/desktop/shell/:id/output`   | `?after=<offset>&plain=1`          | `{ text, offset, status, running, busy, prompt }`: the terminal since `after`                                                     |
| `POST /api/desktop/shell/:id/input`   | `{ text, enter?: true }`           | typed into the shell (409 at a password prompt, or when its shell isn't running)                                                  |
| `POST /api/desktop/shell/:id/:action` | `{ by?: "user" \| "agent", key? }` | `run` (the user's click; needs the run key, "Who can press Run"), `retry`, `skip`, `done`, `cancel`, `dismiss` (the modal closed) |

`{type:"shell", session}` Desktop events ([events.md](events.md)) follow every change. The terminal itself reaches the
GUI over an internal websocket (`/api/desktop/shell/:id/terminal`) and the CLI with
`dimos-desktop terminal read|send|attach --session <id>`. The installer's session is `install`
([install.md](install.md)); an empty `commands` list is an interactive login shell (Settings' Terminal).

## How it works

Desktop starts `bash --noprofile --rcfile <rc> -i` in a PTY when the user presses Run. For each command it writes the
command to a script file and types `__dr <n>` into the shell; that function erases the typed line, runs `bash <script>`
(through `tee` for `needsStdout`), and prints invisible OSC 777 markers where the output starts and ends, with the exit
code. `PROMPT_COMMAND` marks each prompt, so Desktop knows when the shell is idle (an agent's or user's own command has
finished) and when a command was interrupted. Each command is a child of that one shell, on the same terminal, which is
what sudo keys its cached password on (macOS and Linux default to per-terminal tickets).

## Who can press Run

The goal: hard for an app or the agent to press Run for the user (not impossible: see the end).

- **A second origin.** Desktop also listens on `desktop.shell_port` (config.yaml; 0 = `port` + 1), same address,
  network-access and login rules (the session cookie ignores ports, so a logged-in browser is logged in there too). The
  modal (`/?view=shell&id=<id>`), its terminal and the installer's terminal (`/?view=terminal&id=install`) are pages of
  that origin, which Desktop's pages on the main port only frame (`Content-Security-Policy: frame-ancestors` lets only
  pages on the main port frame it). Apps live on the main port, so the browser keeps their JavaScript out of it.
- **Run keys.** Each session has 32 random bytes Desktop never puts in a summary, an event, a log or a JSON route. They
  come only over `/api/desktop/shell-keys` (an internal websocket) on the shell port, from a page of the shell origin
  (`Origin` must be that origin; `Sec-Fetch-Site`, when sent, same-origin). The modal opens it itself and sends its
  session's key back with `POST /api/desktop/shell/<id>/run`, which is 403 without the key or from any other origin or
  port. Nothing on the main port ever holds a key.
- **Terminals.** A session's terminal websocket opens only from the shell origin (a request with no `Origin`, the CLI's
  `terminal attach`, still works), so an app's page can't type into it.
- **Passwords.** At a password prompt `POST …/input`, the agent's `shell_type` and `dimos-desktop terminal send` are
  refused for everyone: a person types the password in the terminal itself (Desktop's window or `terminal attach`).
- **The installer** runs without Run: its commands are Desktop's own (from the components' `dimos.yaml`), and pressing
  Install, `dimos-desktop setup` or `terminal retry` is the consent.

Still open (accepted): any program on this machine (the agent's own bash, an app's backend) can forge `Origin` over
loopback, which needs no login, and fetch a key; an app can still type into the shell between commands through
`POST …/input` (the agent's way to fix a failure) and start the installer; and a page on the main port could try to
trick the user into clicking Run (clickjacking). For remote access forward both ports, keeping them as far apart as
`shell_port` is from `port` (ssh -L 9000:…:5555 -L 9001:…:5556 works): the pages find the shell port relative to their
own, and the shell port lets that main port frame it.

In `deno task ui:dev` the shell port is the real Desktop's (it serves its own built UI), so the modal shows the last
`deno task ui:build`.
