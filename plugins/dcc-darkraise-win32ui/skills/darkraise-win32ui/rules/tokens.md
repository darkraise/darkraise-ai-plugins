# Tokens & color

## Never a literal

Colors, font families, radii, padding, gaps, and font sizes resolve from a
`Tokens.*` value or a named design-system token. A literal does not re-theme: it
survives a mode switch, an accent preset change, and a density change unchanged,
so it drifts out of the design the moment any axis moves.

**Incorrect**

```csharp
new Box { Background = Color.FromArgb(0x1B, 0x1D, 0x21), CornerRadius = 6, Padding = 12 }
```

**Correct**

```csharp
new Box
{
    Background   = Tokens.SurfaceRaised,
    CornerRadius = Tokens.RadiusMd,
    Padding      = Tokens.SpacingMd,
}
```

Look the exact token names up rather than guessing them — `Theming/` in the source,
or the XML docs for the theming namespace.

## Where enforcement exists — and where it does not

The DRUI020 analyzer flags hardcoded theme literals, but it is **scoped to the
assembly named `Darkraise.Win32UI`** and, within it, to `Controls/**` and
`Builder/**`. It returns early for every other compilation.

**A consumer project gets no analyzer backstop at all.** In your own application
or control library, this rule has exactly one enforcer: you. A clean build proves
nothing about whether you followed it.

## The raise ladder

**Six surface roles** plus **three component-internal state steps** — nine tokens,
but they are not nine peers. The roles say what a surface *is*; the steps are for
interaction states within a control.

| Role | Use |
| --- | --- |
| `SurfaceSunken` | Recessed wells: tab strips, scroll tracks, search wells |
| `SurfaceBase` | Page / window background |
| `SurfaceSidebar` | Navigation rails |
| `SurfaceHeader` | Window chrome strips: toolbar, menubar, statusbar |
| `SurfaceRaised` | Cards, dialogs, raised popup bodies |
| `SurfaceOverlay` | Floating overlays: menus, dropdowns, popovers, tooltips |

| Step | Use |
| --- | --- |
| `Surface1` | Component-internal state step 1 — subtle hover on base |
| `Surface2` | Step 2 — hover on raised, stripes |
| `Surface3` | Step 3 — hover on overlay, pressed |

Dark values are tuned so each step is distinguishable at 100% scale on an sRGB
monitor. Light values keep identical role semantics.

## The overlay-hover rule

**Load-bearing.** A hover fill must be at least one *visible* step above its host
surface. On a `SurfaceOverlay` host — menus, dropdown lists — that means
`Surface3`.

**Incorrect**

```csharp
// Menu item on a SurfaceOverlay host.
hoverFill = Tokens.Surface2;
```

`Surface2` is nearly identical to `SurfaceOverlay` in dark mode. The result reads
as **no feedback at all** — the item looks unresponsive, and it will pass a code
review because the code looks reasonable.

**Correct**

```csharp
hoverFill = Tokens.Surface3;
```

The general form: pick the step that is visibly above *this* host, not the step
that happens to be next in the numbering.

## Foreground and the contrast rule

| Token | Use |
| --- | --- |
| `Foreground` | Primary text, meant-to-be-seen glyphs |
| `ForegroundMuted` | Secondary text, descriptions, inactive tab text |
| `ForegroundSubtle` | Placeholders, disabled hints, tertiary metadata |

**Anything meant to be seen uses a `Foreground*` token** — never a `Border*` or
`Surface*` color, which are invisible against nearby surfaces.

**Incorrect**

```csharp
// An empty-state message painted with a border color — effectively invisible.
DrawText("No deployments yet", Tokens.Border);
```

**Correct**

```csharp
DrawText("No deployments yet", Tokens.ForegroundMuted);
```

Functional empty-state glyphs (16–20px) and empty-state invitation text use
`ForegroundMuted` — they are meant to be read. `ForegroundSubtle` is reserved for
placeholders, disabled hints, decorative marks, and large (32–48px) illustrative
art, whose reduced salience is intentional.

## Borders

| Token | Use |
| --- | --- |
| `BorderSubtle` | Row dividers, chrome lines |
| `Border` | Structural outlines: inputs, cards, popovers |
| `BorderHover` | Outline on hovered inputs and bordered interactives |
| `BorderFocus` | Focused outline (accent) |

**All structural borders are 1px.** The only thicker strokes in the entire system
are the 2px active-tab underline and the 3px focus halo.

## Hairlines define structure; shadows define float

**Incorrect**

```csharp
// A card grid where every tile carries a shadow to "add depth".
tile.Shadow = Tokens.ShadowMd;   // on a plain content row, not a floating surface
```

**Correct**

Shadows are reserved for things that genuinely float above the page — popovers,
menus, dialogs, drawers, toasts — and for cards. **Nothing else casts a shadow.**
Structure comes from the 1px border and the raise ladder, not from elevation.

## One accent, four meanings, no leakage

| Token | Means |
| --- | --- |
| `Primary` | Interactive, selected, current |
| `Destructive` | Irreversible or dangerous |
| `Warning` | Caution, at-risk |
| `Success` | Completed, valid |
| `Info` | Neutral information |

The four semantic hues mean **exactly** what they say and are never decorative. The
default accent is deliberately far in hue from all four, so a primary action can
never be mistaken for a destructive or a warning one under any user-selectable
accent preset.

**Incorrect**

```csharp
// Green because the designer liked green here.
chart.SeriesColor = Tokens.Success;
```

**Correct**

Use the chart palette (§3.5) for series color. `Success` means *completed, valid* —
using it decoratively teaches the user that green is meaningless.

### Do not read the reference hexes as exact

The neutral and semantic base hexes are authored byte-exact, but **`Primary` is
not authored at all**: every accent preset is stored as an HSL ramp and resolves
through HSL→RGB when the theme is built. A resolved channel may differ from a
printed reference hex by ±1/255. Verify palette work against the **resolved
token**, never against a hex copied from documentation.

Hover and pressed are derived, not stored: hover is the base lightened 8% in HSL
lightness, pressed is the base darkened 15%.

## The current-item marker

One rule answers "you are here" everywhere. The active item is marked by **the
accent, applied in the surface's own idiom** — never by a free-floating bar that
slides between siblings. Exactly one item is active at a time, and the mark always
carries **at least two signals** (fill or border *and* weight) so it never rides on
color alone.

| Surface | Marker |
| --- | --- |
| Rectangular nav items | `SelectionFill` (Primary at 14%) **plus** a 1px `Primary` border, `Foreground`-600 label, `Primary` icon |
| Top tab strips | A static 2px `Primary` underline on the active tab's bottom edge, inset from each side, `Foreground`-600 label, no fill |
| Steps | The current step's disc gets a 1px `Primary` border and `Primary` number with a `Foreground`-600 label |
| SegmentedControl | The selected segment is a solid fill chip |

The mark is **per-item state, not a travelling object.** When selection changes,
the old item's fill/border/underline clears and the new item's paints in over a
90ms micro-fade. Nothing slides between siblings.

**Incorrect**

```csharp
// An accent rail animating to the selected item's Y position.
_indicator.AnimateTo(selected.Bounds.Y, 200);
```

**Correct**

Clear the previous item's marker and paint the new item's, cross-fading at 90ms.

Controls must not invent other current-item markers — no accent rails, no dot
markers — without a design-system change. The framework's visual signature rests
on the dark-first raise ladder and one restrained accent, not on a decorative
marker.

`SelectionFill` is a **named theme token**, computed once so every accent and mode
switch restyles it centrally. It is `Primary.Base` composited at 14% alpha
straight source-over the host surface — **never** a pre-blended constant, or accent
presets and light/dark switches will miss it.

## The interaction-state contract

Every interactive control implements the full matrix: rest, hover, pressed,
focus-visible, selected/checked, disabled, invalid, busy, and drag where
supported. **A control that skips a state is a bug.**

Two rules inside it are easy to get wrong:

- **Focus-visible is keyboard-only.** A 1px `BorderFocus` outline plus a 3px accent
  halo at 25% alpha outside the control bounds. Mouse or pointer focus shows **no
  ring**.
- **State fills never move content.** Hover, press, and selection change fill,
  border, and foreground colors only. Geometry changes are reserved for the motion
  patterns in §7.

Disabled dims everything — content, fills, and border — at `DisabledOpacity` 0.45.
The dimmed `Border` reads as `BorderSubtle`; do not swap the border token
separately.

## Motion is causality

Animation exists to confirm that an action caused a result. Things fade or scale in
from their trigger, slide from their edge, and settle fast.

**No ambient or looping motion outside explicit progress indicators.** A pulsing
card, a drifting gradient, or a permanently animating icon all violate this.

Standard timings: hover 90ms in / 140ms out; pressed 0ms in / 90ms out; the
current-item marker cross-fades at 90ms.
