# Styling

## The override contract

This is the most consequential styling rule in the kit, and it is documented only
in the package's `CONTRIBUTING.md`, which is **not published to npm**. A consumer
cannot discover it from the installed package.

`theme.css` declares the cascade layer order:

```css
@layer theme, base, components, utilities, overrides;
```

Component CSS lives in `@layer components`. Your Tailwind utilities land in
`@layer utilities`, which comes later. **Therefore your utilities already win over
component-class declarations** — no specificity fight, no escape hatch needed.

### The qualifier, which matters

Your utilities win over *component-class declarations*. They do **not** outrank
everything:

- The package's own `@layer overrides` block holds preset bindings and sits above
  `utilities`.
- Some preset bindings — dark-mode `glass` values among them — are **unlayered**
  entirely, which beats every layer regardless of specificity.

So a utility fighting a preset's own binding will lose. That is the design, not a
bug in the contract. When you need to change what a preset does, change the theme
axis or the preset, never the utility.

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
means you are either fighting a preset binding — which `!` will not reliably win
either — or you have not actually tried the plain utility.

## State variants are independent

Overriding a resting-state color does **not** carry into hover, focus, or active.
Each state is its own declaration and needs its own utility. This surprises
everyone exactly once.

**Incorrect**

```tsx
// Resting state turns red; hover still uses the component's own color.
<Button className="bg-destructive" />
```

**Correct**

```tsx
<Button className="bg-destructive hover:bg-destructive/90 focus-visible:ring-destructive" />
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

`cn` is re-exported from a chunk file in `dist/lib/index.d.ts`. Import it from
`darkraise-ui/lib` — never from a chunk path.

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

Build output contains hash-named chunks such as `Calendar-CWyF6DAE.js`. **The hash
changes on every build.** Reading one to find a type is fine; writing one into
source, an import, or documentation guarantees a break at the next release.

**Incorrect**

```tsx
import type { CalendarProps } from "darkraise-ui/dist/Calendar-CWyF6DAE"
```

**Correct**

```tsx
import type { CalendarProps } from "darkraise-ui/components/calendar"
```
