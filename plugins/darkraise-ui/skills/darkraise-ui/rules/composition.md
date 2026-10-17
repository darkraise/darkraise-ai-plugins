# Composition

## No Radix

Every primitive in this kit is implemented in-house. The package has **zero**
`@radix-ui` dependencies. Installing one adds a second, conflicting behaviour
layer with its own focus management and portal stack.

**Incorrect**

```tsx
import * as Dialog from "@radix-ui/react-dialog"
```

**Correct**

```tsx
import {
  Dialog, DialogTrigger, DialogContent, DialogTitle, DialogDescription,
} from "darkraise-ui/components/dialog"
```

### `asChild` is not universal

Some components take `asChild`, others do not. `Button`, `DialogTrigger`,
`DialogClose` and `TooltipTrigger` have it; `Card` and `Badge` do not. There
is no rule you can infer — **read the `.d.ts`**.

**Incorrect**

```tsx
<Card asChild>          {/* Card has no asChild prop */}
  <article />
</Card>
```

**Correct**

```tsx
<Card className="..." />   {/* card/index.d.ts: no asChild, so compose normally */}
```

## Subpath imports, not the barrel

Subpath imports keep the bundle small. They are also sometimes the *only* way in:
some components are not re-exported from the barrel at all. `MultiSelect` and the
chart parts (`ChartContainer`, …, whose `recharts` peer is optional) are two —
they exist under `dist/components/<name>/` but are absent from `dist/index.d.ts`.

**Incorrect**

```tsx
import { Button, Card, MultiSelect } from "darkraise-ui"   // MultiSelect is not there
```

**Correct**

```tsx
import { Button } from "darkraise-ui/components/button"
import { Card } from "darkraise-ui/components/card"
import { MultiSelect } from "darkraise-ui/components/multi-select"
```

## Parts inside their root; groups are for labels

Compound parts read their root's context and throw outside it
(`DropdownMenuItem must be used within <DropdownMenu>`). A `*Group` is a plain
`role="group"` wrapper: use it with a `*Label` to name a section, not as a
requirement for keyboard navigation.

**Correct**

```tsx
<DropdownMenu>
  <DropdownMenuTrigger asChild><Button variant="ghost">Actions</Button></DropdownMenuTrigger>
  <DropdownMenuContent>
    <DropdownMenuItem>Rename</DropdownMenuItem>
    <DropdownMenuItem>Duplicate</DropdownMenuItem>
    <DropdownMenuSeparator />
    <DropdownMenuItem>Delete</DropdownMenuItem>
  </DropdownMenuContent>
</DropdownMenu>
```

For a command palette in a modal, use `CommandDialog` from
`components/command` rather than nesting `Command` in `Dialog` by hand.

## Overlays always need a title

`Dialog`, `Sheet`, and `Drawer` each require their `*Title` for accessibility. If
the design has no visible heading, keep the title and hide it visually — the
content's `aria-labelledby` points at it. For long content, `DialogBody` and
`SheetBody` pin the header and footer and scroll only the body.

**Incorrect**

```tsx
<DialogContent>
  <p>Delete this deployment?</p>
</DialogContent>
```

**Correct**

```tsx
<DialogContent>
  <DialogHeader>
    <DialogTitle className="sr-only">Confirm deletion</DialogTitle>
    <DialogDescription>Delete this deployment?</DialogDescription>
  </DialogHeader>
</DialogContent>
```

## Full `Card` composition

**Incorrect**

```tsx
<Card>
  <CardContent>
    <h3 className="text-lg font-semibold">Usage</h3>
    <p className="text-sm text-muted-foreground">Last 30 days</p>
    <ChartContainer config={chartConfig} description="Requests per day">…</ChartContainer>
  </CardContent>
</Card>
```

**Correct**

```tsx
<Card>
  <CardHeader>
    <CardTitle>Usage</CardTitle>
    <CardDescription>Last 30 days</CardDescription>
  </CardHeader>
  <CardContent>
    <ChartContainer config={chartConfig} description="Requests per day">…</ChartContainer>
  </CardContent>
</Card>
```

`CardTitle` and `CardDescription` carry the theme's type scale and heading
font. A raw `h3` with utility classes does not follow the `fontSize` or
`headingFont` axes. `Card` takes `surface="card" | "page" | "muted" | "none"`
for its fill — not a `bg-*` class.

## Use the kit's components, not styled divs

Before writing a styled `div`, check this table.

| Intent | Component |
| --- | --- |
| Inline callout | `Alert` |
| Page-level notice | `Banner` |
| Nothing-here state | `EmptyState` |
| Loading placeholder | `Skeleton` |
| Horizontal rule | `Separator` |
| Status pill | `Badge` |
| Transient message | `toast()` from `components/sonner` (mount `Toaster` once) |
| Keyboard hint | `Kbd` |
| Metric readout | `Stat` |
| Progress | `Progress`, or `Spinner` for indeterminate |

**Incorrect**

```tsx
<div className="rounded-md border border-amber-500/40 bg-amber-500/10 p-3 text-amber-200">
  Your trial ends in 3 days.
</div>
```

**Correct**

```tsx
<Alert variant="warning">
  <AlertTitle>Trial ending</AlertTitle>
  <AlertDescription>Your trial ends in 3 days.</AlertDescription>
</Alert>
```

Read `alert.d.ts` for the actual variant union before choosing one.

## Never hardcode English inside a kit component

Components render English by default. To change their strings, use the labels
or locale providers — never fork a component.

**Incorrect**

```tsx
// Copying DataTable's source into the app to change "Rows per page".
```

**Correct — override a few strings**

```tsx
import { UiLabelsProvider } from "darkraise-ui/labels"

const labels = {
  dataTable: {
    rowsPerPage: "Số dòng mỗi trang",
    pageInfo: (page: number, total: number) => `Trang ${page}/${total}`,
  },
  userMenu: { logout: "Đăng xuất" },
}

<UiLabelsProvider value={labels}>
  <App />
</UiLabelsProvider>
```

Override only the keys you need. Providers nest and merge over the nearest
ancestor. **Interpolated labels are functions, not format strings**, so a
language can reorder operands or pluralise in its own function body. Read
`dist/labels/types.d.ts` and `dist/i18n/types.d.ts` for `UiLabels` and
`UiMessages`.

**Correct — a whole language**

The kit ships English and Vietnamese packs and a locale provider that also
drives formatting (`useUiFormatters()`), `lang` and `dir` for portals:

```tsx
import { UiI18nProvider } from "darkraise-ui/i18n"
import { vi } from "darkraise-ui/locales/vi"

<UiI18nProvider locale="vi-VN" locales={[vi]} labels={{ userMenu: { logout: "Thoát" } }}>
  <App />
</UiI18nProvider>
```

Any other language is a partial `UiLocaleDefinition`
(`{ locale, label, dir?, messages }`); missing keys fall back to English.

**An app that also translates its own text** uses the react-i18next adapter.
It needs the optional peers `i18next` and `react-i18next`; core imports do not.

```tsx
import { AppI18nProvider, createDarkraiseI18n, resolveBrowserLocale } from "darkraise-ui/i18n/react-i18next"
import { en } from "darkraise-ui/locales/en"
import { vi } from "darkraise-ui/locales/vi"

const locales = [en, vi]
const storageKey = "my-app.language"
const instance = await createDarkraiseI18n({
  locale: resolveBrowserLocale({ locales, storageKey }),
  locales,
  resources: { en: { translation: {} }, vi: { translation: {} } },
})

<AppI18nProvider instance={instance} locales={locales} storageKey={storageKey} syncDocument>
  <App />
</AppI18nProvider>
```

Switch language with `changeAppLanguage(instance, locale)` and offer the choice
with `LocaleSwitcher` from `components/locale-switcher` (controlled: `value`,
`options`, `onValueChange`, `pending`). Mount the locale provider outside any
`UiLabelsProvider`.

## Reach for a kit hook before writing one

`darkraise-ui/hooks` ships a large set of utility hooks. Check it before writing
your own `useDebounce` or `useMediaQuery`.

```tsx
import { useMediaQuery, useBreakpoint, useDebouncedCallback, useToggle, usePrevious } from "darkraise-ui/hooks"
```

Component-specific hooks live with their component, not in the `hooks` entry
point — `useDialog` from `components/dialog`, `useCombobox` from
`components/combobox`, `useCarousel` from `components/carousel`. These let you
drive a component's behaviour with your own markup when the composed version does
not fit.

Read `dist/hooks/index.d.ts` for the full list (`useReducedMotion` among them).
