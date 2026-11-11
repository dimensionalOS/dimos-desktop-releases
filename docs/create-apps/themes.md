# Themes: looking like Desktop

An app looks like the Desktop around it, in every skin, and follows a skin change live. It gets there by reading a fixed
set of CSS variables (the **theme contract**) and nothing else. This page is the theming reference; the other docs link
here. Each skin's design language (what it's for, its palette, type, shape, depth, motion, do and don't) has its own
page under [themes/](themes/), with a live specimen page:
[Portal](https://jeff-hykin.github.io/dimos-desktop-mirror/create-apps/themes/portal.html),
[Research](https://jeff-hykin.github.io/dimos-desktop-mirror/create-apps/themes/research.html).

## One source of truth: Desktop's `/theme.css`

Every theme value lives in Desktop. It serves every skin's tokens, and the `@font-face` rules for every skin's fonts, as
`/theme.css`. An app at `/apps/<name>/` links it relatively:

```html
<link rel="stylesheet" href="../../theme.css" />
<link rel="stylesheet" href="style.css" />
```

- Portal, the default skin, is the `:root` block. Every other skin is a `html[data-skin="<id>"]` block that sets every
  required token (and `color-scheme`), plus any optional ones it changes.
- `/theme.css` holds only tokens, `@font-face` and the corners overrides: no component styles. Components are yours (or
  dim-app's `.dim-*` classes, written against the same tokens).
- It's generated: `scripts/shell_assets.ts` makes `ui/public/theme.css` from the portal mockup
  (`~/repos/portal-desktop-mockup`, `src.html`'s `:root` block and `themes/<id>.css`). Change a skin there and
  regenerate, never in Desktop's copy.
- **Fonts come from it.** The faces (Inter, IBM Plex Mono, Michroma, Instrument Serif, Share Tech Mono) are served from
  `/shell/fonts/` with `font-display: block`, no network. Don't add a font package, a Google Fonts link or your own
  `@font-face`; use `var(--sans)`, `var(--mono)`, `var(--display)`.

## The token contract

**Required**: every skin sets these, so an app may use any of them without a fallback.

- **color**: `--bg` page, `--fg` text, `--muted-fg` secondary text and labels, `--primary` the one accent (selection,
  active states), `--primary-fg` text on a `--primary` fill, `--ok` `--warn` `--danger` status, `--info` data and tool
  chips
- **surface**: `--surface` panels, `--raised` menus, popovers, toasts and modals, `--input-bg` text boxes, `--hover` a
  hover fill, `--sel` a selected or pressed fill
- **border**: `--border`, `--border-strong`, `--hair` (row dividers)
- **radius**: `--radius` controls, `--radius-sm` parts inside a control and tags, `--radius-lg` panels, `--radius-xl`
  modals and sheets, `--radius-pill` chips, toasts and badges
- **shadow / blur**: `--shadow` panels, `--shadow-lg` menus and modals, `--blur` a `backdrop-filter` value (`none` for
  none)
- **type**: `--sans` UI text, `--mono` data only (rates, IPs, topics, files, ids), `--display` section heads and titles
- **label voice**: `--label-case` section heads' `text-transform`, `--track-label` their `letter-spacing`

**Optional**: always present (the `:root` block derives a default from the required ones; a skin may override). The ones
an app is most likely to want:

- type: `--hud` (controls' font, = `--sans`), `--heading-weight`, `--track-btn`, `--placeholder`
- surfaces: `--card`, `--panel` (dim-app's cards), `--glass` (translucent bars), `--accent` / `--accent-fg` (dim-app's
  hover), `--muted`, `--secondary` / `--secondary-fg`, `--input`, `--track` (a switch's track), `--off` (an idle dot)
- accent and status: `--primary-hover`, `--primary-soft`, `--accent-alt` (a second accent that never means selected:
  recommended, featured), `--danger-fg`, `--violet` (the agent), `--ring`, `--ring-soft` (focus), `--ok-line`
  `--warn-line` `--danger-line` (status outlines), `--head-color` (section heads), `--value-color` (readout values)
- shape and depth: `--radius-round` (dots, knobs), `--shadow-xs` `--shadow-sm` `--shadow-md`, `--glow`, `--glow-accent`
- data: `--code-bg --code-fg --code-kw --code-str --code-num --code-com --code-func --code-loc --code-line`,
  `--cat-1`…`--cat-4` (chart series), `--axis-x --axis-y --axis-z`, `--scene-bg --scene-grid --scene-grid-major` (3D
  views), `--term-bg --term-fg --term-dim` (terminals), `--scrim` (behind a modal)

The full list, with each skin's values, is `/theme.css` itself (`curl http://localhost:<port>/theme.css`). The shell's
own tokens (`--rim-*`, `--chat-*`, `--strip-*`, `--icon-*`, …) are there too; they style Desktop's chat box and dock,
and an app has no use for them.

## Skin, corners, insets

- **Skin**: `html[data-skin="<id>"]`. Settings → Appearance picks it; the shell saves it in localStorage `portal.theme`
  (Desktop's origin, so every app frame shares it; unset means `portal`). `color-scheme` comes with the skin, so native
  controls and scrollbars follow it.
- **Corners**: Settings → Appearance also picks sharp or rounded corners in any skin (localStorage `portal.corners`,
  `/api/ui-settings` `corners`: `theme` keeps each skin's own). The shell sets `html[data-corners="sharp"|"rounded"]`
  and `--dim-corner-radius` (`0px` or `10px`) on every app frame (neither for `theme`), and posts
  `{type: "dimos-corners", corners}`. `/theme.css` carries the rules: the radius tokens either way, and for sharp, every
  corner squared (`border-radius: 0 !important`). Use the radius tokens and corners just work.
- **Insets**: on a wide window Desktop's bottom bar (chat box, blueprint, dock) sits over the bottom of the app's frame.
  The shell posts `{type: "dimos-inset", top, bottom, left, right}` (CSS pixels) on load, on every change, and when the
  page asks with `{type: "dimos-inset-request"}` (to `parent`). On a phone the bar has its own rows, so `bottom` is 0.
  The page turns it into `--dim-inset-top/bottom/left/right` on `:root` (0 outside Desktop; below): keep controls,
  panels and the end of a scrolling list above `var(--dim-inset-bottom)`; backgrounds and 3D views may stay full-bleed.

## Following the skin live

dim-app's `theme.js` (v0.16+) does all of it: links `../../theme.css`, sets `data-skin` and `data-corners` from the
saved keys and again on their `storage` event, and turns `dimos-inset` into `--dim-inset-*`. A plain page does the same
in a few lines (the [simple-html](https://github.com/jeff-hykin/dim-example-html) example has them inline):

```js
function applyTheme() {
    try {
        document.documentElement.dataset.skin = localStorage.getItem("portal.theme") || "portal"
        const corners = localStorage.getItem("portal.corners")
        if (corners === "sharp" || corners === "rounded") {
            document.documentElement.dataset.corners = corners
        } else {
            delete document.documentElement.dataset.corners
        }
    } catch {
        // no storage (outside Desktop): theme.css's :root, Portal, stays
    }
}
applyTheme()
addEventListener("storage", applyTheme)
addEventListener("message", ({ origin, data }) => {
    if (origin === location.origin && data?.type === "dimos-inset") {
        for (const side of ["top", "bottom", "left", "right"]) {
            document.documentElement.style.setProperty(`--dim-inset-${side}`, `${data[side] ?? 0}px`)
        }
    }
})
parent.postMessage({ type: "dimos-inset-request" }, location.origin)
```

In React, use [dimos-react](https://github.com/dimensionalOS/dimos-react): wrap the root in `<AppProvider>` (or just
`<DimThemeProvider>`) and it does all of the above, insets and corners included, following the saved skin live. That's
what the [deno-server](https://github.com/jeff-hykin/dim-example-deno) example's
[`src/main.tsx`](https://github.com/jeff-hykin/dim-example-deno/blob/main/src/main.tsx) does (it vendors dimos-react
with `deno task vendor-dimos-react <tag>`). `useTheme()` gives `{skin, corners, dark, colors}`; a canvas or WebGL view
that needs a token's value reads it from `useThemeColors()`.

## Rules

1. **Only tokens.** Every color, background, border, radius, shadow and font is a `var(--token)`. No hex or `rgb()`
   literals in app CSS (one exception: pure data, like a heat map's ramp, but prefer `--cat-*` and the status colors).
   Tints are `color-mix(in srgb, var(--primary) 12%, transparent)`, not a new color.
2. **No theme switch of your own**, no light/dark toggle, no `prefers-color-scheme` branch: the skin decides, and it is
   set in one place.
3. **Never name a skin** in app CSS or JS (`html[data-skin="research"] .x`). If something looks wrong in one skin, the
   fix is a token (ask for a new optional one), not a skin rule.
4. **Works light and dark.** Check every view in at least Portal (dark, square) and Research (light, rounded) before you
   ship. Don't assume `--fg` is light, `--radius` is 0 or `--shadow` is none.
5. **Mono is for data**: numbers, ids, topics, paths, IPs. UI text is `--sans`; section heads are `--display` (or a mono
   micro-label) with `--label-case` and `--track-label`.
6. **Status means status.** `--ok` `--warn` `--danger` mark state, not decoration. `--danger` may be amber (Portal has
   no red), so pair it with words.
7. **Keep controls above `var(--dim-inset-bottom)`.**

## Checkboxes

Don't ship a bare `<input type="checkbox">`: it ignores the skin and is a ~13px target, too small for a finger on a Steam
Deck or a tablet. Use dim-app's `.dim-check` (a hidden input, a drawn `.box`, or `.ring` for a radio) and make the whole
row the label, so a tap anywhere on it toggles the box:

```html
<label class="dim-check row-check">
    <input type="checkbox" checked />
    <span class="box"></span>
    Auto-upload saved recordings
</label>
```

```css
/* a finger-sized target: the row, not the box */
.row-check {
    min-height: 40px;
    padding: 0 6px;
    gap: 12px;
    border-radius: var(--radius);
    user-select: none;
}
.row-check:hover {
    background: var(--hover);
}
.row-check .box {
    width: 22px;
    height: 22px;
}
```

Without dim-app, draw the same thing from tokens: hide the input (`position: absolute; opacity: 0`), give the `.box` a
`var(--border-strong)` edge on `var(--card)`, fill it with `var(--primary)` when `input:checked + .box`, draw the tick in
`var(--primary-fg)`, and show focus with `input:focus-visible + .box { box-shadow: 0 0 0 3px var(--ring-soft) }`. Both
specimens show it in their skin ("Toggles, chips, status").

## The skins

| id               | name           | look                                                                                  | page                              |
| ---------------- | -------------- | ------------------------------------------------------------------------------------- | --------------------------------- |
| `portal`         | Portal         | dark void, hairlines, square, one sky-blue accent, Michroma heads (the default)       | [portal.md](themes/portal.md)     |
| `green`          | Emerald        | Portal with a turquoise accent and mint heads                                         |                                   |
| `retro`          | Full retro     | Portal in neon: pink accent, Share Tech Mono text, glowing orange heads               |                                   |
| `research`       | Research       | light paper, white hairline cards, rounded, Dimensional blue, Instrument Serif titles | [research.md](themes/research.md) |
| `vibeslop-light` | Vibeslop Light | a chat-app light grey: pill buttons, black accent, all Inter, no label voice          |                                   |
| `vibeslop`       | Vibeslop       | the same, dark                                                                        |                                   |
| `hackerman`      | Hackerman      | black and matrix green, all mono, green glow                                          |                                   |
| `solarpunk`      | Solarpunk      | sand and cream enamel, teal accent, wood tiles (hidden from the pickers)              |                                   |

## What CI checks

- `scripts/check_theme.ts` (`ci.yml`): the `:root` block declares every required token; every skin's block sets every
  required token and `color-scheme` and nothing but custom properties; `/theme.css` holds nothing else; the shell's
  stylesheet names a skin only for the scene, background and decoration allowlist; no other Desktop stylesheet names a
  skin; and every token a component reads without a fallback is one the contract declares.
- `scripts/check_theme_browser.ts` (`.github/scripts/theme_test.sh`, against a built Desktop): in every skin, the
  shell's blueprint bar, chat box, dock and HUD panel, the Settings built-in and (with `--app /apps/<name>/`) an
  installed app show exactly the skin's tokens: the same computed background, corner radius and font. Run it on your
  app: `deno run -A scripts/check_theme_browser.ts http://127.0.0.1:<port> --app /apps/<name>/ --shots /tmp/shots`.
