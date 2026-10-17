# Builder API

## Compose through the `View` factory

`View` is the static entry point — 106 factories covering controls, containers,
and layout.

```csharp
protected override Control BuildView(ShellViewModel vm) =>
    View.Stack(
            Orientation.Vertical,
            16,
            View.Label("Deployments").FontSize(FontSize.Xl).Bold(),
            View.Label().Bind(vm, x => x.Status).Muted(),
            View.Button("Deploy").OnClick(vm.Deploy)
        )
        .Padding(24);
```

## Half the factories return a builder, half return the control

This is the single most misread thing about the API. There is **no uniform rule** —
check the return type.

- **54 factories return a builder**: `Label`, `Button`, `TextBox`, `Stack`, `Card`,
  `Panel`, `DataGrid`, `TreeView`, `ComboBox`, `Drawer`, `Sheet`, `ImageView`, and
  the rest of the composable set.
- **The remainder return a concrete control directly**: `Badge`, `Kbd`, `Spinner`,
  `Skeleton`, `Tooltip`, `Alert`, `Banner`, `Stat`, `Field`, `Avatar`,
  `ButtonGroup`, `Collapsible`, `Accordion`, `Steps`, `Textarea`, `NumberInput`,
  `PasswordInput`, `RadioGroup`, `Toggle`, `Swap`, `DateInput`, `TimePicker`,
  `TagsInput`, `InputOTP`, `Resizable`, `Carousel`, `AngleSlider`, `Chart`,
  `ColorPicker`, `QrCode`, `SignaturePad`, `CascadeSelect`, `NotificationBell`,
  `ModalDialog`, `AlertDialog`, `WindowDialog`, `DropdownMenu`, `HoverCard`,
  `Spacer`, `Divider`, and others.

**Incorrect**

```csharp
Badge badge = View.Badge("New").Build();   // Badge has no .Build() — it is already a Badge
```

**Correct**

```csharp
Badge  badge  = View.Badge("New");          // already the control
Drawer drawer = View.Drawer().Build();      // builder → control
```

`.Build()` exists only on builders. A builder also carries an **implicit conversion
to `Control`**, so passing one where a `Control` is expected works without
`.Build()`:

```csharp
View.Stack(Orientation.Vertical, 8,
    View.Button("Save"),        // builder, implicitly converted
    View.Badge("Draft"))        // already a control
```

You need `.Build()` only when you want the **concrete type** — to reach a member,
or to assign to a `Drawer`/`Sheet`/`ImageView`-typed variable.

> **Historical note.** The framework's known-limitations §15 records a source break
> from the 2026-07-27 parity sweep: `View.ImageView()`, `View.Drawer()`, and
> `View.Sheet()` used to return bare controls and now return builders, with no
> compatibility overloads. This is history, **not a live inconsistency** — old
> sample code that assigned those three directly no longer compiles and needs
> `.Build()`.

## Half the fluent surface is inherited

A concrete builder declares only its own verbs. `ButtonBuilder` has six:
`Variant`, `Size`, `Command`, `OnClick`, `Colors`, `CommandParameter`.

Everything else comes from `ViewBuilder<TControl, TBuilder>`: **`Bind`,
`BindVisibility`, `Enabled`, `Height`, `Margin`, `Name`, `Padding`, `Visible`,
`Width`.**

So when discovering a builder's real surface, grep **both** prefixes:

```bash
grep -oE '<member name="M:Darkraise\.Win32UI\.Builder\.ButtonBuilder\.[^"]*"'  <xml>
grep -oE '<member name="M:Darkraise\.Win32UI\.Builder\.ViewBuilder`2\.[^"]*"'  <xml>
```

Note the backtick-arity form `` ViewBuilder`2 `` — that is how a generic type with
two parameters is spelled in XML doc member names. From source, read
`Builder/<Name>Builder.cs` **and** `Builder/ViewBuilder.cs`.

Grepping only the concrete builder reports a six-method Button builder, which is
wrong in a way that looks right — you will conclude `Padding` does not exist and
reach for a wrapper you do not need.

## Bind, do not assign

**Incorrect**

```csharp
// Reads the value once at construction. Never updates again.
View.Label(vm.Status)
```

**Correct**

```csharp
View.Label().Bind(vm, x => x.Status)
```

`BindVisibility` does the same for visibility. Commands go through `.OnClick(...)`
or `.Command(...)` — do not wire an event handler by hand.

## Authoring a custom control

Only when nothing in the catalogue fits. The full contract is in
`docs/win32ui/extending-controls.md`; this is the part that bites.

### The compliance checklist

Every row is mandatory:

- **Tokens only** — no literal colors, pixel sizes, durations, or font metrics.
  Metrics come from `SpacingXs..SpacingXl`, `Cell`/`CellSm`/`CellLg`,
  `RadiusSm/Md/Lg/Xl`, `RadiusButton`.
- **Full state matrix** — rest, hover, pressed, focus-visible, selected/checked,
  disabled, invalid, busy. A skipped state is a bug.
- **Motion from the catalogue** — durations 90/150/180/240/320ms with the named
  easings and a named pattern (Pop, Slide, Unfold, Cross-fade, Progress).
- **The current-item marker** — use the standard one for the control type; never
  invent dots or rails.
- **The overlay-hover rule** — `Surface3` on a `SurfaceOverlay` host.
- **Focus ring** — `FocusRing.Default(Tokens)` in `ComputeBoxStyle()`, gated on
  `IsFocusVisible`; text wells use `FocusRing.Input(Tokens)`. Mouse focus shows no
  ring.
- **Voice** — sentence case everywhere; no ALL-CAPS outside `Kbd`.

### Rendering rules that bite

Each of these has caused a real bug.

**A state property must invalidate from its setter.** Reject no-op writes with an
equality check, update the field, raise the changed event, then call
`Invalidate()` — plus `InvalidateBoxStyle()` when the box visual depends on it.

**Incorrect**

```csharp
public string Text { get => _text; set => _text = value; }   // paints stale
```

**Correct**

```csharp
public string Text
{
    get => _text;
    set
    {
        if (_text == value) return;
        _text = value;
        TextChanged?.Invoke(this, EventArgs.Empty);
        Invalidate();
        RequestHostLayout();   // text changes measured size
    }
}
```

**Size-affecting properties also need `RequestHostLayout()`.** `Invalidate()` only
repaints at the current bounds. If the property changes measured size — text, icon
size, padding, item count — the host must re-run measure/arrange, or the control
clips until some unrelated layout pass.

**Clamp uniform corner radii before Direct2D.** D2D clamps `RadiusX`/`RadiusY` per
axis independently and produces lopsided corners. Clamp to `min(width, height) / 2`
yourself before any rounded-rect call. The box-model path does this for you; direct
`ctx.FillRoundedRect` calls do not.

**There is no event bubbling.** Hit-testing returns the deepest hit-visible
control, so a click on a `Label` inside your control goes to the `Label`. Set
`IsHitTestVisible = false` on display-only children so input falls through to the
interactive ancestor.

**Theme changes propagate to the main window tree only.** Separate render hosts —
popup HWNDs, overlay windows — must refresh their own tree and repaint. Controls
caching token-derived values resubscribe via `ThemeManager.TokensChanged`. Note
that `ThemeManager.Initialize()` does **not** fire `TokensChanged`.

**`BoxStyle.ClipChildren` defaults to true.** A child's drop shadow painted outside
its bounds is silently cut off by a clipping parent. Do not rely on a shadow
escaping a panel.

**Animation needs a frame source.** `IFrameTickable` controls tick only when
registered with an `OwnerWindow.FrameScheduler`. Content hosted outside the main
tree has no `OwnerWindow` — propagate one, or snap to the final state rather than
latching an "animating" flag nothing will tick.

**Explicit sizes beat stretching parents.** Check
`HasExplicitWidth`/`HasExplicitHeight` in `MeasureOverride` and return the explicit
value, or a consumer's `Width = 200` is ignored inside a filling container.

**Use one text-measurement API per control.** `Renderer.MeasureText`/`DrawText`
treat bold via a weight threshold (>= 600); `IDrawingContext.MeasureText` uses a
style flag. Mixing them on the same string clips the tail of bold text. Cache
measurements keyed on the text to avoid per-frame COM allocations.

**Transforms pivot in world space.** D2D post-multiplies transforms, so a scale or
rotation about a local point must compute the pivot via `TransformPoint`, not local
coordinates.

### Definition of done

A new control ships with the control class, its builder, a demo entry, tests, and
a spec section in `docs/win32ui/design/<category>.md`. `extending-controls.md` §4
walks a complete worked example.
