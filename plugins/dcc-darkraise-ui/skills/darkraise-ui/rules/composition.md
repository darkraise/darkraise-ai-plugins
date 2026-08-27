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

Some components take `asChild`, others do not. `Button`, `Dialog`, and `Tooltip`
have it; `Card` and `Badge` do not. There is no rule you can infer — **read the
`.d.ts`**.

**Incorrect**

```tsx
<Card asChild>          {/* Card has no asChild prop */}
  <article />
</Card>
```

**Correct**

```tsx
<Card className="..." />   {/* check card.d.ts: no asChild, so compose normally */}
```

## Subpath imports, not the barrel

Subpath imports keep the bundle small. They are also sometimes the *only* way in:
some components are not re-exported from the barrel at all. `MultiSelect` is one —
it exists in `dist/components/multi-select.d.ts` but is absent from
`dist/index.d.ts`.

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

## Items inside their group

Compound components expect their documented nesting. A stray item outside its
group loses keyboard navigation and ARIA wiring.

**Incorrect**

```tsx
<DropdownMenuContent>
  <DropdownMenuItem>Rename</DropdownMenuItem>
  <DropdownMenuItem>Duplicate</DropdownMenuItem>
</DropdownMenuContent>
```

**Correct**

```tsx
<DropdownMenuContent>
  <DropdownMenuGroup>
    <DropdownMenuItem>Rename</DropdownMenuItem>
    <DropdownMenuItem>Duplicate</DropdownMenuItem>
  </DropdownMenuGroup>
  <DropdownMenuSeparator />
  <DropdownMenuGroup>
    <DropdownMenuItem>Delete</DropdownMenuItem>
  </DropdownMenuGroup>
</DropdownMenuContent>
```

The same applies to `Select` (`SelectItem` inside `SelectGroup`), `Command`
(`CommandItem` inside `CommandGroup`), and `ContextMenu`.

## Overlays always need a title

`Dialog`, `Sheet`, and `Drawer` each require their `*Title` for accessibility. If
the design has no visible heading, keep the title and hide it visually.

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
    <Chart data={data} />
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
    <Chart data={data} />
  </CardContent>
</Card>
```

`CardTitle` and `CardDescription` carry the theme's type scale. A raw `h3` with
utility classes does not, and will not follow the `fontSize` axis.

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
| Transient message | `sonner` — call `toast()` |
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

Components render English by default. To change their strings, mount
`UiLabelsProvider` — never fork a component.

**Incorrect**

```tsx
// Copying DataTable's source into the app to change "Rows per page".
```

**Correct**

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
ancestor, so a subtree can override a subset. Components render correctly with no
provider mounted.

**Interpolated labels are functions, not format strings.** That is deliberate: a
language that orders the operands differently, or needs a plural form, expresses
that in its own function body. Read `dist/labels/index.d.ts` for the full
`UiLabels` shape.

The package ships no translations and has no concept of a locale. It takes
strings; the app decides which ones.

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

Read `dist/hooks/index.d.ts` for the full list; it is longer than the package
description claims.
