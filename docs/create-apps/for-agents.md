# Making a dimOS app: for coding agents

Terse rules for an agent writing or fixing a dimOS app. The why and the walkthrough are in [index.md](index.md); the
full reference is [apps.md](../apps.md).

## Start

- Copy the example closest to the job, don't start empty:
  [dim-example-html](https://github.com/jeff-hykin/dim-example-html) (page only),
  [dim-example-deno](https://github.com/jeff-hykin/dim-example-deno) (Deno server),
  [dim-example-rust](https://github.com/jeff-hykin/dim-example-rust) (Rust server). Change its name in `flake.nix` (if
  it has one), `dimos.yaml` `title:`, and `icon.svg` ([make-an-icon.md](make-an-icon.md)).
- Repo root must have `dimos.yaml` and `icon.svg`, plus either a `frontend/index.html` and no `flake.nix` (a static app:
  only `frontend/` is served, as is; a root `index.html` with no flake is refused) or a `flake.nix` with
  `packages.<system>.dimosApp` for `aarch64-darwin x86_64-darwin x86_64-linux
  aarch64-linux`. `dimosApp` is either a
  folder with `index.html` or one with `bin/dimos-app-server`.

## Hard rules

1. **Relative URLs only.** The page lives at `/apps/<name>/`: `../../dimos/runs`, `../../api/notifications`, `api/hello`
   (own server). Never hard-code a host, port or the app's name.
2. **Every call outside the app is declared** in `dimos.yaml` `uses:`, under who serves it, as `METHOD path` (`{param}`
   for path parameters): `"@dimos-gateway"` (paths relative to `/dimos`: `GET /runs`), `"@desktop-gateway"` (Desktop's
   own, full paths: `POST /api/notifications`), `"@agentic-gateway"` (relative to `/agent`), or another app's name (its
   public endpoints, relative to it: `dim-controller: [GET api/status]`). Quote `@` names. A value is a list, a version
   range, or `{version, endpoints}`. Undeclared calls get HTTP 403 at runtime. Calls to the app's own server are not
   listed.
3. **Every route the app's server answers is declared** under `provides:`: public in `endpoints:` (method, relative
   path, description) or in `private:` (relative path, trailing `*` for a subtree, optional method).
4. **Every outside origin the page fetches or opens a websocket to** goes in `connects:`. Iframes need nothing.
5. **Using the zenoh-gateway** (topics) requires `uses: "@zenoh-gateway": ">=0.5 <0.6"` and, on spec v1.2, a `zenoh:`
   section listing every key the page reads (`read:`, e.g. `messages: [declare_subscriber, query]`) and writes
   (`write:`, e.g. `messages: [put]`) as `key_exprs` (`*`/`**` wildcards). v1.2 without `zenoh:` = no zenoh access.
   Shape and messages: [apps.md](../apps.md#zenoh-spec-v12-what-an-apps-pages-may-do-on-zenoh).
6. **Required:** `spec-version: v1.2` for an app that uses zenoh (with its `zenoh:` rules), else the lowest minor that
   has every key you use (`v1.0`, or `v1.1` for `optional:`). Never use a key a lower minor doesn't know: unknown keys
   are ignored with a warning, not an error. Never write the deprecated `dimos-api:`, `dimos:`, `agent:` or `private:`
   (top level): `uses:` and `provides:` replace them.
7. **A server reads `DIMOS_APP`** (JSON env var) and serves HTTP on its `socket`. Use `dataDir` for files (the checkout
   is replaced on update). Ignore unknown fields.
8. **Theme:** link `../../theme.css` and use only its tokens; follow the saved skin live (React: the deno-server
   example's `src/theme.ts` `useDesktopTheme()`). No own theme switch, no hard-coded colors or fonts, never name a skin.
   Keep controls above `var(--dim-inset-bottom)`. Tokens and rules: [themes.md](themes.md).
9. **No secrets in the repo.** Binary-cache tokens go in CI secrets, set by the human.
10. **Never actuate without a user action.** Publish on command topics (cmd_vel, ...) only from a drive control, never
    at page load or while idle; arm the deadman on the first drive input. dim-app's `app.publisher()` does this. Call
    skills that move the robot only on a click.

## Check before you finish

```sh
dimos-desktop app check .     # exits 1 on an undeclared call, route or origin
nix build .#dimosApp          # must build; add `result` to .gitignore
dimos-desktop app check . --run   # a server must start from DIMOS_APP alone, listen on its socket and stay up
```

`app check` reads string literals. A literal that only looks like an endpoint: add a `dimos-yaml-check: ignore` comment
on its line. A path built at runtime slips past it, but not past the runtime check: declare it anyway.

Then install it (App Store → Install From URL, or `dimos-desktop install <git url>`), open it, and confirm no refusal
notification appears. Tag releases `vX.Y.Z`: Desktop installs the newest tag.

## Fixing a refusal

The user may paste Desktop's **Copy message**: it names the app, the refused `METHOD /path` (or origin), the file
(`dimos.yaml`) and the YAML to add. Merge it into the keys already there (one `uses:`, one `provides:`), run
`dimos-desktop app check .`, commit, push, and tag. If the call shouldn't happen at all, remove the call instead.

## Useful endpoints

- `GET /dimos/blueprints`, `GET /dimos/blueprints/<name>` (modules, their streams and types), `GET /dimos/runs`,
  `POST /dimos/runs`: the dimos gateway (its OpenAPI is served by the installed dimos).
- `GET /dimos/msgs.js`: decodes/encodes every dimos message
  (`import { decodeMessage, geometry_msgs } from "../../dimos/msgs.js"`, `decodeMessage(zenohMessage)`,
  `geometry_msgs.Twist.encode({ linear: { x: 0.3 } })`); declare `"@dimos-gateway": [GET /msgs.js]`; a bundled page
  loads it with a runtime `import(new URL("../../dimos/msgs.js", location.href).href)`.
- `POST /api/notifications` `{ title, body, kind }`; `POST /api/open-app`; from a page,
  `parent.postMessage({ dimosShell: 1, type: "open_app", app }, location.origin)`.
- Another app's `provides:` endpoints at `/apps/<other>/...` (declare them under `uses: <other>:`; that app must be
  installed).
