# Styling

## The override contract

This is the most consequential styling rule in the kit. It is documented in the
repository's `CONTRIBUTING.md` and `docs/custom-styles.md`, **neither of which
is published to npm**, so a consumer cannot discover it from the installed
package.

`styles.css` opens with the cascade layer order:

```css
@layer properties, theme, base, style.base, style.mode, style.when, style.preset, style.fallback, components, utilities, overrides;
```

Component CSS lives in `@layer components`; the active style and preset write
their paint tokens into the `style.*` layers below it. Your Tailwind utilities
land in `@layer utilities`, which comes later. **Therefore your utilities
already win over component-class declarations** — no specificity fight, no
escape hatch needed.

### The qualifiers, which matter

- **Colour tokens are inline.** The engine writes `--primary`, `--background`
  and the rest as inline styles on `<html>`; no stylesheet rule beats them.
  Change colour through the theme axes.
- **Paint tokens are overridable from `@layer overrides`.** To change a style
  token app-wide (`--card-radius`, `--btn-shadow`, …), set it on `:root` inside
  `@layer overrides`, or define a style or preset — see
  [theming.md](./theming.md).
- **A few kit rules are unlayered** — the forced-colours rules and the
  reduced-motion guard — and beat every layer. Do not fight them.
- **Never import the kit stylesheet into a layer of your own**
  (`@import "darkraise-ui/styles.css" layer(vendor)`); that reorders every kit
  layer and is unsupported.

```css
@import "darkraise-ui/styles.css";

@layer overrides {
  :root { --card-radius: 0.25rem; }
}
```

## Never `!important`, never the `!` modifier

**Incorrect**

```tsx
<Card className="!bg-muted !p-6" />
```

**Correct**

```tsx
<Card className="bg-muted p-6" />
```

The layer order already puts you on top of the component class. Reaching for `!`
means you are fighting an inline colour token or an unlayered kit rule — which
`!` will not fix — or you have not actually tried the plain utility.

## State variants are independent

Overriding a resting-state color does **not** carry into hover, focus, or active.
Each state is its own declaration and needs its own utility. This surprises
everyone exactly once.

**Incorrect**

```tsx
// Resting state turns red; hover still uses the component's own color.
<Button className="bg-destructive-solid" />
```

**Correct**

```tsx
<Button className="bg-destructive-solid hover:bg-destructive-solid/90 focus-visible:ring-destructive-edge" />
```

Better still, use the variant that already means this:

```tsx
<Button variant="destructive" />
```

## `className` carries layout, not color or typography

The variant and size props carry the theme's opinion about how a component looks.
`className` is for where it sits and how big its box is.

**Incorrect**

```tsx
<Button className="bg-purple-600 px-8 text-lg font-bold" />
```

**Correct**

```tsx
<Button variant="secondary" size="lg" className="w-full" />
```

If no variant expresses what you need, that is a signal to check the `.d.ts` for
one you missed before overriding.

## `cn()` for conditional classes

`cn` merges Tailwind classes and resolves conflicts. A template literal does not —
it happily emits `p-2 p-4` and leaves the winner to source order.

**Incorrect**

```tsx
<Card className={`p-4 ${isActive ? "ring-2 ring-primary" : ""} ${dense ? "p-2" : ""}`} />
```

**Correct**

```tsx
import { cn } from "darkraise-ui/lib"

<Card className={cn("p-4", isActive && "ring-2 ring-primary", dense && "p-2")} />
```

Import `cn` from `darkraise-ui/lib`, which is also safe in a React Server
Component — never from a file path inside `dist`.

## Tailwind 4 only

There is no `tailwind.config.js` in a darkraise-ui project and creating one will
not do what you expect. Configuration is CSS-first.

**Incorrect**

```js
// tailwind.config.js — this file has no effect
module.exports = { theme: { extend: { animation: { slide: "..." } } } }
```

**Correct**

```css
/* src/styles/globals.css */
@import "darkraise-ui/styles.css";

@theme {
  --animate-slide: slide 1.2s ease-in-out infinite;
}

@keyframes slide {
  0%   { transform: translateX(-100%); }
  50%  { transform: translateX(200%); }
  100% { transform: translateX(-100%); }
}
```

The kit's stylesheet must be imported before your `@theme` block, and it is the
only stylesheet import the app needs — it carries the tokens, the layer order, and
every component's CSS.

## Never write a chunk filename

Build output contains hash-named JavaScript chunks such as `dist/chunk-<HASH>.js`.
**The hash changes on every build.** Writing one — or any other `dist/` path —
into source, an import, or documentation guarantees a break at the next
release. `package.json` `exports` does not expose them anyway.

**Incorrect**

```tsx
import type { CalendarProps } from "darkraise-ui/dist/components/calendar/Calendar"
```

**Correct**

```tsx
import type { CalendarProps } from "darkraise-ui/components/calendar"
```
