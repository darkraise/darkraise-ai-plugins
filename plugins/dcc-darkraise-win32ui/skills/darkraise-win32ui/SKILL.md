---
name: darkraise-win32ui
description: Manages Darkraise.Win32UI desktop applications — building views, composing controls, theming, layout, MVVM, and draml markup. Applies when working with Darkraise.Win32UI, the View builder, DarkraiseScreen, .drui or .draml files, DRUI diagnostics, or any project referencing the Darkraise.Win32UI package.
user-invocable: true
---

# Darkraise.Win32UI

A desktop UI framework built directly on Win32 and Direct2D. No WPF, no WinForms, no third-party packages — windows are real `HWND`s, painting goes through Direct2D and DirectWrite, and the framework is NativeAOT compatible. Targets `net10.0-windows` and requires Windows.

**These rules were written against the `docs/win32ui/` revision `53cae267` (2026-08-22).**

**Drift runs backwards here.** The published package lags the source repository. If this skill describes an API that is absent from the installed package's XML docs, the consumer needs a package upgrade — do not invent a workaround, and do not assume the skill is wrong.

## Principles

1. **Raised from dark.** Hierarchy is expressed by surfaces stepping toward light, not by decoration. The light theme derives from the same surface roles; it is never designed separately.
2. **Hairlines define structure; shadows define float.** Every container is delimited by a 1px border. Shadows are reserved for things that genuinely float — popovers, menus, dialogs, drawers, toasts — and for cards. Nothing else casts a shadow.
3. **One accent, four meanings, no leakage.** The accent means *interactive or current*. Red, amber, green, and blue mean destructive, warning, success, and info, and are never used decoratively.
4. **Motion is causality.** Animation exists to confirm that an action caused a result. No ambient or looping motion outside explicit progress indicators.
5. **Density with hierarchy.** This is a desktop tool framework — 32px control rows, 13px body text, compact spacing — but density never comes from shrinking type below the scale or removing padding below the tokens.

## Current Project Context

How the framework is referenced:

```
!`grep -rh --include=*.csproj --include=Directory.Packages.props -oE '<(Package|Project)Reference[^>]*Darkraise[^>]*' . | sort -u`
```

What is in the package cache:

```
!`ls ~/.nuget/packages/darkraise.win32ui/ ~/.nuget/packages/darkraise/ 2>/dev/null`
```

A `ProjectReference` means the source tree is available and is the better source. A `PackageReference` means read the XML docs. The second probe also covers central package management, where the `.csproj` carries no version at all.

## Look up the API before you write

**Two XML doc files matter, not one:**

```
~/.nuget/packages/darkraise.win32ui/<version>/lib/net10.0-windows/Darkraise.Win32UI.xml
~/.nuget/packages/darkraise/<version>/lib/<tfm>/Darkraise.xml
```

The second is easy to miss and load-bearing. The **MVVM surface** — `DarkraiseScreen`, `Set(ref …)`, `[RootViewModel]`, the conductors — lives in the **Darkraise core assembly**, not in Darkraise.Win32UI. Sending an MVVM lookup to `Darkraise.Win32UI.xml` searches a file that does not contain the answer.

These files are verbose; never read one whole. Grep for the member prefix of the type in question:

```bash
grep -oE '<member name="M:Darkraise\.Win32UI\.Builder\.ButtonBuilder\.[^"]*"' <path-to-xml>
```

**That prefix alone is not enough.** Builders derive from `ViewBuilder<TControl,TBuilder>`, so the inherited half of the fluent surface — `Padding`, `Margin`, `Width`, `Height`, `Visible`, `Enabled`, `Name`, and the generic `Bind` — sits under the mangled generic-arity prefix. Grep for it too:

```bash
grep -oE '<member name="M:Darkraise\.Win32UI\.Builder\.ViewBuilder`2\.[^"]*"' <path-to-xml>
```

Grepping only the concrete builder reports `ButtonBuilder` as having eight methods, which is wrong in a way that looks right.

When the framework is project-referenced, prefer the source: `src/Darkraise.Win32UI/` and `src/Darkraise/`. Read `Builder/<Name>Builder.cs` **together with** `Builder/ViewBuilder.cs` for the same reason.

Note that the framework builds with `NoWarn CS1591`, so a member with no XML summary is normal and does not mean the member is private or unsupported.

## Critical Rules

These rules are **always enforced**. Each links to a file with Incorrect/Correct code pairs.

### Tokens & color → [tokens.md](./rules/tokens.md)

- **Never a literal.** Colors, fonts, radii, padding, gaps, and font sizes resolve from `Tokens.*`.
- **A consumer project gets no analyzer backstop.** DRUI020 is scoped to the framework assembly; a clean build proves nothing about your code.
- **The overlay-hover rule.** A hover fill on a `SurfaceOverlay` host must be `Surface3`, never `Surface2`.
- **One current-item marker.** Two signals, per-item state, never a travelling rail.

### Builder API → [builder.md](./rules/builder.md)

- **About half the `View` factories return a builder, half return the control.** Check the return type; `.Build()` applies only to the builder ones.
- **Half the fluent surface is inherited.** Look up `ViewBuilder<TControl,TBuilder>` too.
- **Bind, don't assign.** `.Bind(vm, x => x.Property)` and `.OnClick(vm.Method)`.

### Layout → [layout.md](./rules/layout.md)

- **Only `Box` and `Border` paint.** Every other layout primitive is invisible skeleton.
- **Scroll is the only legitimate escape valve for overflow.**
- **Containers own spacing, children do not.**

### MVVM & draml → [mvvm-draml.md](./rules/mvvm-draml.md)

- **`FooViewModel` resolves to `FooView` by convention.**
- **These types live in the Darkraise core assembly,** not Darkraise.Win32UI.
- **Markup views are compiled, not parsed.** A mistyped binding is a compile error.

### Limits → [limitations.md](./rules/limitations.md)

- **Check this file before promising any capability.**
- **No UI Automation or screen-reader support.** Never claim accessibility compliance.

## Key Patterns

```csharp
// Colors resolve from tokens — a literal does not re-theme.
.Background(Tokens.SurfaceRaised)                  // correct
.Background(Color.FromArgb(0x1B, 0x1D, 0x21))      // wrong

// Bind to the view model; do not assign once and hope.
View.Label().Bind(vm, x => x.Status)               // correct
View.Label(vm.Status)                              // wrong: never updates

// Commands go through OnClick, not an event handler you wire yourself.
View.Button("Save").OnClick(vm.Save)               // correct

// Layout primitives own spacing — never manual coordinates.
View.Stack(Orientation.Vertical, 16, a, b, c)      // correct
// setting child.X / child.Y by hand                  wrong

// Roughly half the View factories return a builder, half return the control.
Drawer drawer = View.Drawer().Build();             // View.Drawer() is a builder
Badge badge   = View.Badge("New");                 // View.Badge() is already a Badge
// Check the return type before reaching for .Build() — it exists only on builders.
```

## Control Selection

Organised by the framework's own sixteen design-spec categories.

| Need | Use |
| --- | --- |
| Actions | `Button`, `ButtonGroup`, `Toggle`, `ToggleSwitch`, `Swap` |
| Text input | `TextBox`, `Textarea`, `InputGroup`, `NumberInput`, `PasswordInput`, `TagsInput`, `InputOTP`, `Field` |
| Date & time | `DateInput`, `TimePicker`, `DatePicker`, `Calendar` |
| Selection | `CheckBox`, `RadioButton`, `RadioGroup`, `ComboBox`, `MultiSelect`, `ListBox`, `SegmentedControl`, `CascadeSelect` |
| Range & pickers | `Slider`, `AngleSlider`, `RatingGroup`, `ColorPicker` |
| Status & indicators | `Badge`, `Avatar`, `Kbd`, `Stat`, `Spinner`, `Skeleton`, `ProgressBar`, `CircularProgressBar`, `Steps`, `NotificationBell` |
| Feedback | `Alert`, `Banner`, `NotificationBanner`, `Toast`, `Highlight`, `Marquee` |
| Overlays | `Tooltip`, `HoverCard`, `Popover`, `DropdownMenu`, `ContextMenu` |
| Modals & dialogs | `ModalDialog`, `AlertDialog`, `Drawer`, `Sheet`, `WindowDialog`, file dialogs |
| Window & shell | window chrome, `WindowTitleBar`, `TrayIcon`, `StatusBar` |
| Containers | `Card`, `Collapsible`, `Accordion`, `Resizable`, `Carousel`, `Divider`, `Panel`, `ScrollViewer` |
| Navigation | `Sidebar`, `MenuBar`, `TabControl`, `ToolBar`, `AppBar`, `Pagination` |
| Data | `DataGrid`, `TreeView`, `Chart` |
| Code | `CodeDisplay` |
| Media & motion | `Icon`, `QrCode`, `SignaturePad`, `CountdownTimer`, `Animate`, `Transition` |
| Layout | `Box`, `Border`, `Label`, `Stack`, `Inline`, `Center`, `Grid`, `GridPanel`, `DockPanel`, `WrapPanel`, `UniformGrid`, `Spacer` |

Each category has a full design spec at `docs/win32ui/design/<category>.md` in the framework repository. Where a spec and the design system disagree, **the design system wins** — it says so itself.

## Workflow

1. **Read the injected context.** Decide source lookup versus XML-doc lookup from the first probe.
2. **Look up the type**, including its base builder — the inherited half is easy to miss.
3. **Check [limitations.md](./rules/limitations.md)** before promising any capability.
4. **Write the code**, resolving every visual from a token.
5. **Verify against the Critical Rules** above before you finish.

## Quick Reference

```csharp
// Program.cs
using Darkraise.Win32UI.Application;

public static class Program
{
    [STAThread]
    public static void Main() => new App().Run();
}

// App.cs
public class App : DarkraiseApplication
{
    protected override void ConfigureServices(IServiceRegistry services)
    {
        // Register your own services; AddWin32UI() runs afterwards and respects overrides.
    }

    protected override void Configure(ApplicationConfiguration config)
    {
        config.ApplicationName = "Hello Win32UI";
        config.Theme = AppTheme.Dark;
        config.Accent = AccentPreset.Blue;
        config.Assemblies = [typeof(App).Assembly];
    }
}

// ViewModels/ShellViewModel.cs
[RootViewModel]
public class ShellViewModel : DarkraiseScreen
{
    private string _status = "Ready";

    public string Status
    {
        get => _status;
        set => Set(ref _status, value);
    }

    public void Greet() => Status = $"Hello at {DateTime.Now:T}";
}

// Views/ShellView.cs — resolved by convention: ShellViewModel → ShellView
public class ShellView : ViewBase<ShellViewModel>
{
    protected override Control BuildView(ShellViewModel vm) =>
        View.Stack(
                Orientation.Vertical,
                16,
                View.Label("Hello, Win32UI").FontSize(FontSize.Xl).Bold(),
                View.Label().Bind(vm, x => x.Status).Muted(),
                View.Button("Greet").OnClick(vm.Greet)
            )
            .Padding(24);
}
```

`Run()` builds the DI container, scans the configured assemblies for view models, resolves the `[RootViewModel]` and its view, then pumps the message loop until shutdown.
