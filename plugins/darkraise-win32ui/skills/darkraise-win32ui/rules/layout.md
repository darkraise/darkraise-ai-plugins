# Layout

## The primitives, and which ones paint

**Only `Box` and `Border` paint.** Everything else is invisible skeleton that owns
spacing and structure.

| Primitive | Role |
| --- | --- |
| `Box` | Paints: background, border, radius, shadow |
| `Border` | Paints: a bordered wrapper |
| `Label` | Text |
| `Stack` | Linear layout, explicit orientation |
| `Inline` | Horizontal linear layout |
| `Center` | Centres a single child |
| `Grid` / `GridPanel` | Row/column layout with `Auto`/`Star`/`Pixel` tracks |
| `DockPanel` | Edge docking with a filling remainder |
| `WrapPanel` | Flow layout that wraps |
| `UniformGrid` | Equal cells |
| `Spacer` | Fixed empty extent |

`Border` has **no `View.Border()` factory** — `View.Box(...)` is the painting
container you reach through the factory. Construct `Border` directly when you need
it, or use a `Box` with border tokens set.

`View.Spacer(int size)` and `View.Divider()` return a `Control`, not a builder.

**Incorrect**

```csharp
// Positioning children by hand.
child1.X = 0;  child1.Y = 0;
child2.X = 0;  child2.Y = 32;
```

**Correct**

```csharp
View.Stack(Orientation.Vertical, Tokens.SpacingMd, child1, child2)
```

Containers own spacing. A child never sets its own position, and a gap is the
container's `spacing`, never a `Spacer` inserted between every pair.

## Sizing — how a control decides its box

Available space flows **down** from the parent; content size flows **up** from
children. Per axis, sizing resolves in strict priority:

1. **Explicit** — a set `Width`/`Height` always wins. The control renders at that
   size and is pinned to its slot's start, never stretched.
2. **Stretch** — with no explicit size, the control fills what the parent offers on
   an axis the parent stretches: a vertical `Stack`'s cross axis, a `Grid` `Star`
   track, a `Dock` `Fill`.
3. **Hug** — otherwise the control is only as large as its content.

Treat **unbounded available space as a first-class state**, not a magic number. A
control measured at unbounded size reports its content size; one measured at a
definite size may fill it.

`MinWidth`/`MaxWidth`/`MinHeight`/`MaxHeight` (0 = unset) clamp every measured
result: **max applies first, then min, and min wins over max.**

One exception worth knowing: a **Stretch**-aligned child's cross-axis size derives
from the container's cross extent and never consults the child's own `Min`. A tight
`StackLayout` can therefore arrange a Stretch child narrower than its declared
`MinWidth`.

## Overflow and clipping

Default is **visible** — content paints where it is laid out, even past its
container's box. A container clips only when it opts in.

**The ink-vs-layout rule is load-bearing.** Two kinds of overflow are handled
separately:

- **Layout overflow** — a child's *content* extending past the parent's box. A
  clipping container removes this.
- **Ink overflow** — a control's own **shadow, focus halo, and outline**, which
  render outside its box by design. A control's own ink is **never** clipped by its
  own clip; only an *ancestor's* clip removes a descendant's ink.

That is how a container can clip its children while still casting its own shadow.

Remember that `BoxStyle.ClipChildren` defaults to **true**, so a child's shadow
painted outside its bounds is silently cut off by a clipping parent.

## Text overflow

Single-line text **clips at the trailing edge** by default — it never bleeds.

`Label` is the exception: any non-wrapping `Label` ellipsizes on truncation by
default, whether its width is explicit or hug-measured and then constrained.

Two opt-ins for everything else:

- **Ellipsis** — `IDrawingContext.DrawText(..., trim: true)` trims a truncated
  single-line run to `…` instead of a hard cut. No further plumbing required.
- **Wrap** — `Label.Wrap` (off by default) reflows onto multiple lines.
  `Textarea` is the multi-line input.

An editable single-line `TextBox` horizontally scrolls to keep the caret visible
rather than truncating.

## Scroll is the only escape valve

When content is genuinely larger than its region, `ScrollViewer` is the **sole**
sanctioned answer. It measures content at unbounded size, shows a bar when content
exceeds the viewport, reserves the gutter so content lays out beside rather than
under the bar, always clips the viewport, and scrolls through the shared
`SmoothScroller`.

`Overflow` is `Vertical` (default), `Horizontal`, `Both`, or `Hidden` (clip, no
bars).

**Incorrect**

```csharp
// Shrinking type below the scale so a list fits.
itemLabel.FontSize = 9;
```

**Correct**

```csharp
View.ScrollViewer(View.Stack(Orientation.Vertical, Tokens.SpacingSm, items))
```

Overflow is never resolved by letting content paint beyond its region, and never by
shrinking type below the scale.

## Distribution — how a container splits space

| Manager | Main axis | Cross axis | Doesn't fit |
| --- | --- | --- | --- |
| `StackLayout` (`Stack`, `Inline`) | Hug — sum of children; `Justify` distributes *positive* free space | `Align`, Stretch by default | Overflows past the edge |
| `DockLayout` (`DockPanel`) | Each child hugs its dock edge; the last child or `Fill` takes the remainder | Stretch to the cross extent | Remainder goes negative → overlap |
| `GridLayout` (`GridPanel`) | `Auto` hugs, `Star` fills leftover, `Pixel` fixed | Fill the cell | `Star` collapses to 0; `Auto`/`Pixel` overflow |
| `FlowLayout` (`WrapPanel`) | Flow, then **wrap** to a new line | Line height is the tallest item | Wraps — the only manager that does |
| `UniformGridLayout` (`UniformGrid`) | Equal cells | Fill the cell | Cells shrink with count |

### No shrink

**Unlike flexbox, no manager compresses children when space is tight.** There is no
`flex-shrink` equivalent — children overflow, which is exactly why clipping is the
load-bearing backstop.

Plan for it: if a row can run out of room, either clip it, scroll it, or use
`WrapPanel`, which is the one manager that wraps.

`Stack.Wrap` and `Grid.Responsive` are **accepted-but-inert stubs**. Setting them
compiles and does nothing. Wrapping is `WrapPanel` only.

## Content alignment

Alignment runs on the same two axes as distribution, named by role because they
swap with orientation. The **main axis** is the direction the container lays out;
the **cross axis** is perpendicular. A vertical `Stack`'s main axis is vertical.

- **Cross-axis — `Align`:** `Start`, `Center`, `End`, **`Stretch` (default)**.
  Stretch fills the cross extent unless the child has an explicit cross size; the
  others place the child at its content size.
- **Main-axis — `Justify`:** **`Start` (default)**, `Center`, `End`, `Between`,
  `Around`. It distributes only *positive* free space — with no slack, `Justify`
  does nothing.

## The spacing scale

Spacing comes from `SpacingXs` through `SpacingXl`; cell metrics from `Cell`,
`CellSm`, `CellLg`; radii from `RadiusSm/Md/Lg/Xl` and `RadiusButton`.

**Density never comes from shrinking type below the scale or removing padding below
the tokens.** This is a desktop tool framework — 32px control rows, 13px body text,
compact spacing — but a strict type and spacing scale is what keeps dense screens
legible. If a layout does not fit, the answer is scroll, wrap, or fewer elements,
never a smaller font.

## Relayout versus repaint

`Invalidate()` repaints at the current bounds. It does **not** re-measure.

A change that affects measured size — text, icon size, padding, item count — also
needs `RequestHostLayout()` so the host re-runs measure and arrange. Without it the
control clips or leaves a gap until some unrelated layout pass happens to fix it.
