# Known limitations

**Read this before promising any capability.** The most damaging failure in this
framework is not wrong code — it is confidently designing a feature the framework
does not support, then discovering it three files in.

All seventeen entries below come from `docs/win32ui/known-limitations.md`. Each
says what to do instead.

## 1. No UI Automation or screen-reader support

There is no UIA provider. Screen readers see nothing meaningful.

**Never claim accessibility compliance, WCAG conformance, or screen-reader
support.** Keyboard navigation and focus-visible rings *are* implemented and are
worth doing well — say that instead, and be explicit that assistive-technology
support is absent if the question comes up.

## 2. IME / CJK text input depends on the control

`TextBox` hosts a real in-place Win32 `EDIT` child and inherits standard IME
behaviour — CJK composition works as in any native field. Controls that implement
their own text editing do not get this for free.

For a CJK-facing app, prefer `TextBox` and `Textarea` over custom text surfaces,
and verify composition behaviour on anything else.

## 3. x64 / ARM64 only

No x86. Do not offer a 32-bit build.

## 4. Windows version floor

Designed and tested on **Windows 11**. The DWM polish attributes it uses —
`DWMWA_WINDOW_CORNER_PREFERENCE`, `DWMWA_BORDER_COLOR`, `DWMWA_CAPTION_COLOR`,
`DWMWA_TEXT_COLOR`, all introduced in build 22000 — are guarded to no-op on
Windows 10, where windows and popups fall back to **square corners and default
frame colors**. Per-monitor-V2 DPI awareness needs Windows 10 1703 or later.

So a Windows 10 user gets a working app that looks less finished. Do not promise
identical chrome across versions.

## 5. Localization is partial

Calendar and date controls are culture-aware — day and month names come from
`CultureInfo.CurrentCulture`, with a per-control `Culture` override.

But **built-in chrome strings are English literals with no resource pipeline**:
dialog button captions (`OK`, `Cancel`, `Yes`, `No` in `MessageDialog` and
`InputDialog`) and the `FileBrowserView` UI text cannot be translated.

A fully localized app needs its own dialogs for those cases.

## 6. DPI

Per-monitor-V2 is implemented at the window boundary: the visual tree, layout, and
input run in logical units, while render targets, window sizing, mouse input,
native `EDIT` children, and overlay windows convert at the boundary.
`WM_DPICHANGED` rescales a live window.

Work in logical units and let the boundary convert. Do not apply your own DPI
scaling.

## 7. Layout and render contract gaps

Design-system §13 describes the intended contract; parts are not implemented. The
two that bite most:

- **No `min-content`.** The hug axis measures at `max-content` only, so a container
  cannot shrink a child honestly.
- **No shrink.** No layout manager compresses children when space is tight — they
  overflow, and clipping is the backstop.

See [layout.md](./layout.md). `Stack.Wrap` and `Grid.Responsive` are inert stubs.

## 8. No collection virtualization in `ScrollViewer`

`ScrollViewer` measures and arranges **every** child on every layout pass. A scroll
host with hundreds of real child controls keeps them all alive regardless of what
is visible.

Do not build a long list by putting hundreds of controls in a `ScrollViewer`. Use
`DataGrid` or `TreeView`, which have their own virtualization, or window the data
yourself.

## 9. Window sizing is clamped to the monitor work area

`WM_GETMINMAXINFO` caps a top-level window at the nearest monitor's work area, so a
window can never be sized — interactively or programmatically — larger than that.

Consequence for tooling: **a full-page screenshot of content taller than the screen
cannot be taken in one frame** by growing the window. Capture such content another
way.

## 10. `DrawImageData` takes `byte[]` only

`IDrawingContext.DrawImageData` accepts a `byte[]` and nothing else. Plan the
conversion.

## 11. The sanctioned §9 ellipsis

"Go to symbol…" is a deliberate exception to the voice rules. Do not treat it as
licence for ellipses elsewhere.

## 12. `MenuPopup` renders its whole item list

`Menu` dropdowns and every `ContextMenu` are painted by `MenuPopup`, which has **no
scroll offset, no visible-range window, and no row cap**. A menu with hundreds of
items pays the full measure/arrange/paint cost every pass, and a list taller than
the screen **has no way to reach its tail**.

`DropdownMenu` is the exception — it virtualizes.

So: keep menus short. If a list can grow unbounded, use `DropdownMenu`, a
`ComboBox`, or a search surface, never a `ContextMenu`.

## 13. GDI+ image formats only

Whatever GDI+ decodes, and nothing else. No WebP, no AVIF, no SVG rasterization.
Convert at build time or bring your own decoder to a `byte[]`.

## 14. Animated GIFs render their first frame only

There is no frame animation. For motion, use the framework's own animation
patterns, not an animated image.

## 15. The 2026-07-27 `View` factory source break

`View.ImageView()`, `View.Drawer()`, and `View.Sheet()` changed from returning bare
controls to returning builders, with no compatibility overloads.

**This is history, not a live inconsistency.** See [builder.md](./builder.md) for
what the factories return today and when `.Build()` is needed.

## 16. Popup corner rounding collapses Rounded and Pill

DWM's corner preference is a four-value enum, too coarse to distinguish the
framework's `Rounded` and `Pill` radii on popup windows. Both render the same.

Do not design a popup whose identity depends on a pill silhouette.

## 17. `CodeDisplay` Copy/Cut require a selection

The context-menu Copy and Cut entries act on a selection and do nothing without
one. There is no implicit copy-current-line.
