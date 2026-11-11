# Research

`html[data-skin="research"]` in `/theme.css`.
**[Open the live specimen](https://jeff-hykin.github.io/dimos-desktop-mirror/create-apps/themes/research.html)**: every
token, the type scale and the components built from them. How theming works for an app: [../themes.md](../themes.md).

## Mood

Dimensional's research site and cloud console: a lab notebook, not a cockpit. Warm paper, white cards drawn with a
hairline and a whisper of shadow, one Dimensional blue accent, Instrument Serif for titles, Inter for the interface and
IBM Plex Mono for small uppercase labels and data. The night scene behind the desktop becomes a faint blue technical
wireframe on paper (mountains and grid in the accent, the sun logo washed to a sepia sunset), and an app loading shows
paper with a faint 40px blueprint grid. It is the light skin, made for daylight, screenshots and papers.

## Palette

| Token             | Value                   | Role                                                                    |
| ----------------- | ----------------------- | ----------------------------------------------------------------------- |
| `--bg`            | `#f5f4ef`               | paper: the page                                                         |
| `--fg`            | `#20211f`               | ink, a warm near-black                                                  |
| `--muted-fg`      | `#6b6a63`               | secondary text, labels                                                  |
| `--primary`       | `#293ce4`               | Dimensional blue: the one accent, section heads, primary buttons, focus |
| `--primary-hover` | `#2232c4`               | a pressed or hovered primary fill                                       |
| `--primary-fg`    | `#ffffff`               | text on blue                                                            |
| `--ok`            | `#2f9e5b`               | green: running, connected                                               |
| `--warn`          | `#d97a1e`               | orange: attention                                                       |
| `--danger`        | `#c2412f`               | brick red: failure, destructive actions, the app bar's ✕                |
| `--danger-fg`     | `#ffffff`               | text on red                                                             |
| `--info`          | `#3a5bd9`               | data, links in data                                                     |
| `--violet`        | `#3a5bd9`               | the agent (the same blue family, no purple)                             |
| `--surface`       | `#ffffff`               | cards and panels                                                        |
| `--raised`        | `#ffffff`               | menus, popovers, modals                                                 |
| `--card`          | `#ffffff`               | dim-app's cards                                                         |
| `--glass`         | `rgba(255,255,255,.92)` | bars over the desktop                                                   |
| `--input-bg`      | `#f5f4ef`               | text boxes sit in paper (white once focused)                            |
| `--accent`        | `#fbfaf7`               | a button's hover fill                                                   |
| `--hover`         | `rgba(32,33,31,.05)`    | hover fill                                                              |
| `--sel`           | `rgba(41,60,228,.08)`   | selected / pressed fill                                                 |
| `--border`        | `#e2e0d7`               | card and control edges                                                  |
| `--border-strong` | `#cfccc0`               | hovered edges                                                           |
| `--hair`          | `#eae9e2`               | row dividers                                                            |
| `--track`         | `#d9d7cd`               | a switch's track, off                                                   |
| `--off`           | `#c9c7bc`               | an idle status dot                                                      |
| `--placeholder`   | `#9a998f`               | placeholder text, code comments                                         |
| `--code-bg`       | `#f7f6f1`               | code blocks, the agent's messages                                       |
| `--term-bg`       | `#20211f`               | terminals stay dark (text `#f5f4ef`, dim `#9a998f`)                     |
| `--scrim`         | `rgba(0,0,0,.25)`       | behind a modal                                                          |

## Type

- **Instrument Serif** (`--display`) for titles, greetings, the clock and card names: 30px/1.1 page titles, 22px an
  app's title (17px in Desktop's app bar), sentence case, `-0.01em` tracking, weight 400. Never uppercase, never small.
- **Inter** (`--sans`, `--hud`) for the interface: 14px/1.55 body, 13px weight-500 buttons with no tracking
  (`--track-btn: 0`), 12.5px field labels; `font-feature-settings: "cv11", "ss01"`.
- **IBM Plex Mono** (`--mono`) for the micro-labels and data: section heads are 500 10.5px mono, uppercase
  (`--label-case`), `0.14em` tracking (`--track-label`), in blue (`--head-color: --primary`, `--head-font: --mono`);
  card heads, table heads and labels the same in `--muted-fg`; chips 12px, badges 500 10px; values, ids, versions
  12.5px.

## Shape

Gently rounded: `--radius` 8px (buttons, inputs), `--radius-sm` 6px, `--radius-lg` 10px (cards), `--radius-xl` 14px
(modals, sheets), `--radius-pill` 999px (chips, badges, the ask box), `--radius-round` 50% (dots, knobs). Every card has
a 1px `--border`; rows are divided by `--hair`. A 3px left rule (`--list-rule`) in the row's color marks a notification,
a banner or a picked search row.

## Depth

- Cards: `--shadow: 0 1px 2px rgba(32,33,31,.05), 0 8px 24px rgba(32,33,31,.06)`, a lift you feel more than see.
  `--shadow-xs: 0 1px 2px rgba(32,33,31,.05)` for small things.
- Floating: `--shadow-md: 0 12px 32px rgba(32,33,31,.12)` (menus), `--shadow-lg: 0 24px 60px rgba(32,33,31,.14)`
  (modals, sheets).
- Glass: `--glass` white at 92% with `--blur: blur(10px)`.
- No glow anywhere (`--glow: none`, `--glow-accent: none`). Focus is the blue border plus a 3px
  `--ring-soft: rgba(41,60,228,.12)` ring, and a focused text box turns white.

## Motion and sound

Still. Research turns off every shell flourish: no turning rim (`--rim-spin: none`), no smoke, bursts, light cone or
glitch; the chat box is a plain `--border-strong` hairline that turns blue on hover, with a soft blue 3px halo while in
use. What moves is `0.15s ease` on hover and focus. UI sounds are the shell's and the same in every skin (Settings → UI
sounds); an app adds none.

## Iconography

App icons keep their own colors and sit on a dark tile (`--icon-tile: #1b1c22`, `--icon-radius: 10px`), with no filter
at rest and `brightness(1.12)` on hover; no hover brackets. The robot-type icons have a Research twin,
`ui/src/assets/robot_icons/<type>_research.svg`: dark-ink line art (`#1a1d2e` → `#2b3678`) with a soft fill and scan
lines in one muted accent per type: robot and custom Dimensional blue `#293ce4`, dog teal `#0b8577`, arm moss `#5a7d4d`,
drone rose `#a75a64`, humanoid violet `#5b36d6`, wheeled walnut `#916b4a`. The Launcher draws the twin on any light page
(`html[data-light]`).

## Do and don't

- **Do** build with white cards on paper: `--card`, a `--border` hairline, `--radius-lg`, `--shadow`.
- **Do** head sections with mono micro-labels in blue, and give a page one serif title.
- **Do** use blue for exactly one primary action per view; other buttons are white with a hairline, or ghost.
- **Do** use `--danger` red for destructive actions and failures: here it is a true red.
- **Don't** set UI text or buttons in the serif, or titles in mono.
- **Don't** add glows, neon, gradients or dark panels (terminals and code-heavy views are the exception: `--term-bg`).
- **Don't** hard-code `#fff` or the paper color; a card is `var(--card)`, the page is `var(--bg)`, so the same CSS is
  right in Portal.
- **Don't** round with literal radii or pills of your own; `--radius-pill` is a pill here and square in Portal.
