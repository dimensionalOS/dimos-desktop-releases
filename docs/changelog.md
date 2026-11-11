# Changelog for app authors

What changed that an app has to care about, newest first, and what to do about it. Nothing else: Desktop ships often
and most of it is invisible to an app, so a release only appears here when it **asks something of an app**, **lets an
app do something new**, or **changes what an existing file means**.

Three version numbers decide what an app can use, and they move independently:

| what                  | where it is                                                | what it decides                                               |
| --------------------- | ---------------------------------------------------------- | ------------------------------------------------------------- |
| **Desktop** `X.Y.Z`   | `dimos-desktop --version`, `GET /info`                     | the API an app calls and the `DIMOS_APP` it is handed          |
| **dimos.yaml spec**   | `spec-version:` in the app's own file                      | how Desktop reads the rest of that file ([apps.md](apps.md))   |
| **dim-app SDK**       | the tag `tools/vendor.js` ran from, or the URL a page pins  | the helpers the app's own code calls                           |
| **dimos gateway API** | `GET /gateways/dimos/info` → `api`                         | the dimos endpoints under `uses: "@dimos-gateway"`              |

**A newer Desktop never breaks an app.** `dimos.yaml` is additive only, unknown keys are ignored with a warning, and a
file at a newer spec minor still installs on an older Desktop. So nothing here is urgent; it is what to pick up when
you next touch an app. The one thing that *is* worth doing promptly is anything under **Do this** below.

## Desktop 0.2.229 · spec v1.5 · dim-app v0.26.0 · gateway API 8.2.0

**Do this:** add `uses: <provider>: env:` to your `dimos.yaml` listing the `DIMOS_APP` values your server reads, and
stop printing `DIMOS_APP.secrets`.

- **`uses: <provider>: env:`** (spec v1.5) names the values an app needs of that provider's environment, keyed by
  variable or by a path inside one holding JSON — `DIMOS_APP.machineId`, `DIMOS_APP.secrets.zenohGatewayToken`. Declare
  the **field**, not the variable: every app server is handed `DIMOS_APP`, so naming it says nothing, while `machineId`
  has existed only since 0.2.226. `dimos-desktop app check` then reports a value this Desktop doesn't set before
  anything runs, and a launch that can't resolve one writes `warn: DIMOS_APP.x is empty…` into the app's own log. Only
  `type` in a `schema:` is checked; the rest of a schema is documentation.
- **`DIMOS_APP.secrets`** is a new section holding the app's secrets, its `zenohGatewayToken` among them (which stays
  where it was as well, so nothing breaks). **Never print it and never pass it on.** Desktop redacts that token out of
  the log it serves precisely because apps print the whole object at startup; skipping one section is what makes that
  unnecessary for the next secret. Every app in this org now prints `DIMOS_APP` with `secrets` removed — copy that.
- **The zenoh namespace is `<machine-id>/<home-slug>`**, where it used to be `dimos-desktop/<host>-<port>`. An app is
  handed it (`DIMOS_APP.zenohNamespace`, `zenohPrefix`; pages get `GET /gateways/desktop/management/gateways/zenoh`), so
  nothing to do — **unless you have the old string written down somewhere**, in a script that exports
  `DIMOS_ZENOH_NAMESPACE` or a hand-written `z_sub`. Those move to the new namespace or stop seeing each other. A
  `zenoh.namespace` a user set is untouched.
- **The dimos gateway's `config` event is one topic per setting**: `<ns>/dimos/events/config/<setting>`, where
  `<setting>` is a key of `GET /gateways/dimos/config` (`recordingsDir`, `path`). The payload carries no value, so
  `GET /config` stays the one answer and a cache can never disagree with the event. Subscribe to the setting you read,
  or to `<ns>/dimos/events/**` for all of them — a single `*` matches one chunk and misses these.
- **dim-app `watchRecordingsDir(cb)`** keeps the recordings folder current off that event, and `eager` is now one
  option on the watchers rather than two functions: eager (the default) re-asks at once and hands the callback the
  value, `{ eager: false }` calls back with `null` and leaves the round trip to your next read.
- **dim-app `emptyState`** actions take a `ui` name, which becomes the button's `data-ui` for a press log.
- Desktop **0.2.228** is the zenoh-gateway 0.5.32 release: every encoded message reaching a page carries its own
  `msg.header` (`stamp`, `frameId`, `seq`) on clouds, depth, images, video and audio, and `subscribe(key, { metadata:
  false })` opts out. It also moved the dimos gateway into Desktop's own copy of its `desktop-gateway` tag, so a dev
  branch in your checkout can no longer break the gateway that serves it. Nothing for an app to do.
- `dimos-desktop app check` reports a **build manifest whose version disagrees with `dimos.yaml`'s** (0.2.227). That
  number is what your app reports of itself: `CARGO_PKG_VERSION` in a log line, `app_version` in every recording's
  metadata. If you bump only `dimos.yaml` on release, the crate silently rots — dim-go2-dash stamped `0.5.37` onto
  recordings for thirty releases. Put the check in CI, not in a `#[test]`: a nix build narrows its source to the crate
  and cannot read `dimos.yaml`.

## Desktop 0.2.226

**Do this:** nothing, unless your app read `DIMOS_HOME` or Desktop's `config.yaml` — then stop.

- **`DIMOS_APP.machineId`** names this machine in a fleet (32 hex, stable across a rename). If your app writes
  recordings, tag them with it. Older Desktops leave it out, which is what `uses: env:` above is for.
- **An app depends on `DIMOS_APP` and the gateways, and on nothing else.** Desktop's own settings moved out of the
  environment into `config.yaml`, its home became `--home <dir>`, and keys and passwords moved to `secrets.yaml`
  (0600). An app that opened Desktop's `config.yaml` to read something out of it (dim-go2-dash did, for `machine_id`)
  has to ask instead.
- **Where recordings go is the dimos gateway's answer**, `GET /gateways/dimos/history/recordings`, with
  `DIMOS_APP.recordingsDir` as the offline fallback. There used to be three answers that agreed only when
  `recordings.dir` was set, which is how a run launched from the UI wrote where the Recordings app wasn't looking.

## Desktop 0.2.221 · spec v1.4

**Do this:** move your `uses: "@desktop-gateway"` paths under `/gateways/desktop/` and set `spec-version: v1.4`.

- Desktop's own API moved to the `/gateways/...` layout: `/gateways/desktop/*` (ui, management, info, update,
  recordings, topics, settings), `/gateways/dimos/*`, `/gateways/agent/*`. In a v1.4 file `"@desktop-gateway"` paths are
  relative to `/gateways/desktop/`; in a v1.3-or-lower file they are Desktop's old full paths, which still answer.
- Built-in apps (`@launcher`) are used like any other app in `uses:`.

## spec v1.3

**Do this:** rewrite `provides:` as an OpenAPI 3.1 document.

- `provides:` is an OpenAPI 3.1 document, its private paths in `x-private:`, with Desktop's own `x-when` on `info:` and
  on each operation. The old `{description, endpoints: [...], private: [...]}` shorthand still reads, into the same
  thing.

## spec v1.2

**Do this — this one changes what an existing file means.** If you re-stamp a file to v1.2 or newer, it must have a
`zenoh:` section or its pages can do **nothing** on the bus.

- `zenoh:` says what the app's pages may read and write, as zenoh's own access-control config. A file at v1.1 or lower
  gets read and write on `**` whatever it says; from v1.2 on, a file **without** the section gets nothing at all.

## dim-app, the versions worth picking up

The SDK is vendored (`tools/vendor.js` from the tag you want) or pinned in a page's import URL, so an app moves when
you move it. `vendor.js` follows a file's imports, so a helper that grew a dependency costs you nothing.

| version     | what it changed for you                                                                                        |
| ----------- | -------------------------------------------------------------------------------------------------------------- |
| **v0.26.0** | `watchRecordingsDir()`; `eager` as one option on the watchers; `emptyState` action `ui`                         |
| **v0.25.1** | its zenoh-gateway client is v0.5.32's, where every encoded message carries `msg.header` (stamp, frameId, seq)   |
| **v0.25.0** | `sharedConfig()` / `watchSharedConfig()` — needs gateway API 8.1.0, so check before adopting                    |
| **v0.24.0** | `recordingsDir()` asks the gateway; `recordingsDir` is no longer parsed out of `DIMOS_APP` by the SDK           |
| **v0.23.2** | `client.setLinkBandwidth(n)`, for a known link speed instead of the gateway's estimate (needs a 0.5.30 gateway) |
| **v0.22.0** | `getZenoh().lease({ publish, subscribe })`, so one page owns a command topic                                    |

**A vendored file you edit loses the edit.** `tools/vendor.js` overwrites whatever is in the folder, so a local change
to a vendored SDK file disappears the next time anyone refreshes it — silently. dim-go2-dash carried one for months
(an `emptyState` action's `ui`) and it was found only when every app was refreshed at once. Send it upstream instead.

## How this is kept

A Desktop release that asks something of an app adds a section here, in its release commit. If you find something
missing, it is a bug in this page: the rule is that an app author can read this page alone and know what to change.
