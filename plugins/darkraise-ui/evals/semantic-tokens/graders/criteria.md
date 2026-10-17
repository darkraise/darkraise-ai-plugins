The response must style through darkraise-ui's semantic tokens, never raw Tailwind
color utilities. Every theme axis recomputes the semantic tokens at runtime, so a
raw color silently opts the element out of theming and will not follow a mode
switch.

Pass when:

- Colors come from semantic tokens: `bg-card`, `text-card-foreground`,
  `text-muted-foreground`, `bg-background`, `border-border`, `bg-primary`,
  `bg-destructive`, `bg-success`, `bg-warning`, `bg-info`, or another token from
  the theme's declared set.
- The `Card` component and its `CardHeader` / `CardTitle` / `CardDescription` /
  `CardContent` parts are used rather than a styled `div` with a raw heading.
- No manual `dark:` color override appears — the tokens already handle both modes.

Fail when:

- Any raw palette utility appears as a color: `bg-slate-900`, `text-gray-400`,
  `border-zinc-800`, `text-emerald-500`, and so on.
- The card is a hand-built `div` carrying its own border, background, and radius.
- The response adds `dark:` variants to work around colors it hardcoded.
