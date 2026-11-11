# Portal

The default skin (`:root` in `/theme.css`, `html[data-skin="portal"]` or none).
**[Open the live specimen](https://jeff-hykin.github.io/dimos-desktop-mirror/create-apps/themes/portal.html)**: every
token, the type scale and the components built from them. How theming works for an app: [../themes.md](../themes.md).

## Mood

A night console at the edge of a synthwave horizon: a near-black void, a faint grid floor running to the horizon, the
logo as a setting sun of neon arcs, status in the screen's corners like a HUD. Everything an app draws is the calm layer
in front of that: quiet dark surfaces and hairlines, with color carried by a few soft accents instead of frames and
ornaments. The mockup's "professional pass" sets the voice: sans for UI text, mono only for data, one blue accent, color
reserved for status. **Containers don't glow**: light comes from the accent (focus, a pressed control, a status dot),
never from a panel.

## Palette

| Token                | Value                       | Role                                                                  |
| -------------------- | --------------------------- | --------------------------------------------------------------------- |
| `--bg`               | `#05070d`                   | the void: page                                                        |
| `--fg`               | `#ece8f0`                   | text, a warm lavender white                                           |
| `--muted-fg`         | `#8e8898`                   | secondary text, labels                                                |
| `--primary`          | `#7cc8ec`                   | the one accent: selection, focus, the prompt, active and on states    |
| `--primary-fg`       | `#05070d`                   | text on a `--primary` fill                                            |
| `--ok`               | `#8fd4a8`                   | mint: running, connected                                              |
| `--warn`             | `#e8bf6a`                   | amber: attention                                                      |
| `--danger`           | `#e8bf6a`                   | the same amber: **Portal has no red**; failure is amber plus words    |
| `--info`             | `#8fcfe0`                   | cyan: data, tool chips, `code`                                        |
| `--violet`           | `#9fb4d8`                   | the agent                                                             |
| `--surface`          | `#0e0c13`                   | panels: the chat box, dock, HUD panels, app bar                       |
| `--raised`           | `#0e0c13`                   | menus, popovers, toasts, modals (the same: depth comes from the line) |
| `--input-bg`         | `#0c0b10`                   | text boxes                                                            |
| `--hover`            | `rgba(255,255,255,.04)`     | hover fill                                                            |
| `--sel`              | `--primary` 13% (color-mix) | selected / pressed fill                                               |
| `--card`             | `--surface` 92% (color-mix) | dim-app's cards: a touch of the scene shows through                   |
| `--glass`            | `--surface` 82% (color-mix) | translucent bars over the desktop                                     |
| `--border`           | `rgba(255,255,255,.1)`      | panel and control edges                                               |
| `--border-strong`    | `rgba(255,255,255,.22)`     | hovered edges, the portal                                             |
| `--hair`             | `rgba(255,255,255,.08)`     | row dividers                                                          |
| `--head-color`       | `= --primary`               | section heads                                                         |
| `--scrim`            | `rgba(4,3,8,.62)`           | behind a modal                                                        |
| `--scene-grid-major` | `#1c1a22`                   | 3D views' major grid lines                                            |

## Type

- **Inter** (`--sans`, `--hud`) for everything you read or press: 13.5px body in the shell, 14px/1.55 in dim-app, 12px
  buttons with `0.04em` tracking.
- **IBM Plex Mono** (`--mono`) only for data: rates, IPs, topics, files, ids, versions, readout values; 11.5–12.5px.
- **Michroma** (`--display`) for section heads and titles only, always small, uppercase (`--label-case: uppercase`) and
  tracked wide (`--track-label: 0.2em`; an app's name in its bar `0.22em`): 9–12px in panels, 18px at the most for a
  page title. Michroma is wide; at body sizes it shouts. Never in a control (buttons and inputs are `--hud`).
- Heading weight 400 (Michroma has one). Chips and small buttons keep normal case (`--chip-case: none`).

## Shape

Square. Every radius token is `0px` (`--radius`, `-sm`, `-lg`, `-xl`, `-pill`, and `--radius-round`, so status dots are
squares too). dim-app squares every corner in a square skin (`* { border-radius: 0 !important }`) so a stray rounded
corner can't leak in. Structure is drawn with 1px lines: `--border` around a panel or control, `--hair` between rows,
`--border-strong` on hover. A colored 2px left rule (`--list-rule`) marks a picked row, a banner or a notification.

## Depth

- Panels: no shadow (`--shadow: none`, `--shadow-xs/-sm: none`). Separation is the hairline and the surface step from
  `--bg` to `--surface`.
- Things that float (menus, modals): `--shadow-lg: 0 20px 60px rgba(0,0,0,.7)`,
  `--shadow-md: 0 12px 30px
  rgba(0,0,0,.6)`.
- Glass: translucent bars use `--glass` with `--blur: blur(10px)`.
- Glow is for the accent only: `--glow: 0 0 8px` of `--primary` at 60%, `--glow-accent: 0 0 12px` at 30%. Focus is a 1px
  accent ring plus `0 0 14px rgba(124,200,236,.25)`; a status dot glows in its own color.

## Motion and sound

Portal's flourishes belong to the shell, and all stop under `prefers-reduced-motion`:

- the chat box's rim is a conic gradient in the logo's pastels (mint, peach, pink, lavender) that turns once every 5s
  while the box is in use (`--rim-spin`), with a smoky glow drifting around it (`--chat-smoke`) and color bursts on the
  idle rim (`--chat-burst`);
- the agent-finished strip slides up out of the chat box and its text glitches in for 0.25s, sliced with a pink/blue
  split (`--strip-glitch`, `--strip-flicker`);
- the portal opens with `0.2s cubic-bezier(.2,.8,.2,1)`; hovers and fills ease over `0.15s`.

UI sounds are synthesized in the browser (oscillators and noise, no audio files) in swappable packs, the default
`terminal` (square-wave blips, like an old console), for hover, click, type, open and close app, portal, send and reply
(Desktop's `/shell/sfx.js`; Settings → UI sounds, localStorage `portal.sfx`, `portal.pack`, `portal.vol`). An app gets
the motion it needs from `0.15s ease` transitions and adds no UI sounds of its own.

## Iconography

App icons are neon line glyphs with a white-hot core (`--icon-core: 0.24`), slightly quieted at rest
(`--icon-filter: saturate(.97) brightness(.94)`) and lit on hover with a 1px cyan/pink RGB split; targeting brackets
frame a hovered dock icon. No tile behind them, square corners. The robot-type icons are
`ui/src/assets/robot_icons/
<type>.svg`: the same neon style, one accent per type. To draw one:
[../make-an-icon.md](../make-an-icon.md).

## Do and don't

- **Do** let the void show: big areas are `--bg`, panels are `--surface`/`--card` with a `--border` hairline.
- **Do** keep the accent rare: one primary action per view, the selected row, the focused field.
- **Do** say what failed in words; the color alone (amber) doesn't read as an error.
- **Do** set section heads in `--display`, `--label-case`, `--track-label`, at 9–12px.
- **Don't** add a shadow or glow to a panel or card.
- **Don't** introduce a red, a second accent or a gradient fill; tints are `color-mix` of a token.
- **Don't** set body text, buttons or long labels in Michroma, or prose in mono.
- **Don't** round a corner with a literal radius; use the tokens (0 here, rounded in Research).
