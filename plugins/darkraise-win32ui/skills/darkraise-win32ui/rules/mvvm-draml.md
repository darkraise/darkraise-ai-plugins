# MVVM & draml

## These types live in the core assembly

**Read this before looking anything up.** `DarkraiseScreen`, `Set(ref …)`,
`[RootViewModel]`, `DarkraisePropertyChangedBase`, and the conductors are in the
**Darkraise core assembly** at `src/Darkraise/Mvvm/` — **not** in
Darkraise.Win32UI.

So MVVM lookups go to:

```
~/.nuget/packages/darkraise/<version>/lib/<tfm>/Darkraise.xml
```

Searching `Darkraise.Win32UI.xml` for `DarkraiseScreen` finds nothing and reads as
"this type does not exist", which is the single most likely lookup mistake in this
framework.

## Convention-based MVVM

`FooViewModel` resolves to `FooView`. `[RootViewModel]` marks the entry point that
`Run()` resolves after scanning the assemblies named in
`ApplicationConfiguration.Assemblies`.

**Incorrect**

```csharp
// Constructing and wiring the view by hand.
var vm = new ShellViewModel();
var view = new ShellView();
view.DataContext = vm;
window.Content = view.BuildView(vm);
```

**Correct**

```csharp
[RootViewModel]
public class ShellViewModel : DarkraiseScreen { }

public class ShellView : ViewBase<ShellViewModel>
{
    protected override Control BuildView(ShellViewModel vm) => /* … */;
}
```

`Run()` builds the DI container, finds the `[RootViewModel]`, resolves its view by
name convention, and pumps the message loop until shutdown.

## Change notification

**Incorrect**

```csharp
public string Status
{
    get => _status;
    set => _status = value;      // nothing re-renders
}
```

**Correct**

```csharp
public string Status
{
    get => _status;
    set => Set(ref _status, value);
}
```

`Set<T>(ref T member, T value, [CallerMemberName] string? propertyName = null)`
fills the property name in for you and returns whether the value actually changed.
Never pass the name explicitly from a normal property setter.

## Lifecycle

`DarkraiseScreen` provides:

- `OnInitializedAsync(CancellationToken)` — once, on first activation. **Load data
  here**, not in the constructor.
- `OnActivatedAsync(CancellationToken)` — every activation.
- `OnDeactivatedAsync(bool close, CancellationToken)` — every deactivation;
  `close: true` means permanent.

Plus the shared infrastructure: `Resolve<T>()` for DI, `Logger`, `Dialog`, `IsBusy`
with the `RunBlockUITask(...)` overloads, `DisplayName` (used as the window title
for the root view model), and `TryCloseAsync(bool?)`, which invokes the
framework-wired `CloseAction` to close the hosting window.

**Correct**

```csharp
protected override async Task OnInitializedAsync(CancellationToken cancellationToken)
{
    await RunBlockUITask(async () =>
    {
        Items = await Resolve<ICatalogService>().LoadAsync(cancellationToken);
    });
}
```

`RunBlockUITask` sets `IsBusy` around the work, which is what drives the busy state
of the interaction-state contract. Do not manage a busy flag yourself.

## Multi-screen navigation

A real application is not one screen. `AppShellViewModel` derives from
`OneActiveConductor<DarkraiseScreen>` and hosts pages with activation lifecycle.

**Correct**

```csharp
[RootViewModel]
public class ShellViewModel : AppShellViewModel
{
    public ShellViewModel()
    {
        Items.Add(Resolve<DeploymentsViewModel>());
        Items.Add(Resolve<SettingsViewModel>());
    }
}
```

The conductor owns which child is active and calls the activation and deactivation
hooks on the way in and out. Do not swap a `Content` property by hand — that skips
the lifecycle and leaks whatever the previous screen held.

## Markup views are compiled, not parsed

`.drui` and `.draml` files handed to the compiler as `AdditionalFiles` are compiled
by `Darkraise.Win32UI.Generators` into control trees at build time. There is no XML
parsing, no reflection, and no trimmer roots at runtime.

The generator emits a `ViewBase<TViewModel>` partial with bindings and command
wiring resolved against the real view-model type, so **a renamed or mistyped
property is a compile error, not a silent runtime no-op.**

```xml
<ItemGroup>
  <AdditionalFiles Include="**/*.drui" />
  <AdditionalFiles Include="**/*.draml" />
</ItemGroup>
```

```xml
<?xml version="1.0" encoding="utf-8"?>
<View ViewModel="HelloApp.ViewModels.SignInViewModel">
  <Stack Gap="Md">
    <Label Text="Sign in" FontSize="Lg" Bold="true" />
    <TextBox Text="{Bind UserName}" Placeholder="User name" Width="240" />
    <CheckBox Text="Remember me" IsChecked="{Bind RememberMe}" />
    <Divider />
    <Button Text="Sign in" Variant="Primary" Command="SignInCommand" />
  </Stack>
</View>
```

## Runtime-loaded draml is a different mechanism

`DramlView.LoadFile` parses `.draml` at runtime, for when views should be editable
data rather than compiled code.

**Those files are `Content`, not `AdditionalFiles`.**

**Incorrect**

```xml
<!-- A file intended for DramlView.LoadFile, wired as AdditionalFiles -->
<AdditionalFiles Include="Views/Dynamic.draml" />
```

It gets compiled into the assembly and is not copied to the output, so
`LoadFile` cannot find it at runtime.

**Correct**

```xml
<Content Include="Views/Dynamic.draml" CopyToOutputDirectory="PreserveNewest" />
```

Compiled views get the compile-time binding check; runtime-loaded views do not.

## `DruiSchema.xsd` does not appear in your project

The schema ships in the generator package under `content/`. **A `PackageReference`
does not copy `content/` into the consuming project**, so the file will not show up
in your source tree and there is nothing to reference by relative path.

For editor validation and IntelliSense over markup, point the editor at the
package-cache path:

```
~/.nuget/packages/darkraise.win32ui.generators/<version>/content/DruiSchema.xsd
```

## Diagnostics

Compiled markup fails the build with a specific code. Diagnose from this table
rather than searching the web.

| Rule | Meaning |
| --- | --- |
| DRUI001 | XML parse failure in a view file |
| DRUI002 | Unknown element |
| DRUI003 | Missing required attribute |
| DRUI004 | View declares no root control |
| DRUI005 | Unknown attribute |
| DRUI006 | View model type not found |
| DRUI007 | View model property not found |
| DRUI008 | Feature not supported in compiled views |
| DRUI009 | Invalid attribute value |
| DRUI010 | Attribute does not support `{Bind}` |
| DRUI011 | `CommandParameter` without `Command` |
| DRUI012 | View model does not derive from `DarkraiseScreen` |
| DRUI013 | Invalid element content |
| DRUI014 | `Command` property is not an `ICommand` |

DRUI020 is separate and unrelated to markup — it is the hardcoded-theme-literal
analyzer, and it only runs against the framework's own source. See
[tokens.md](./tokens.md).

Two of these are worth calling out because the fix is not obvious:

- **DRUI008** means the feature works in code-built views but not in compiled
  markup. Build that part of the view in C# rather than trying to express it in
  markup.
- **DRUI012** means the type named in `ViewModel=` does not derive from
  `DarkraiseScreen`. Markup views require a screen, not a plain object.
