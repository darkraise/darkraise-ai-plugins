Every visual must resolve from a `Tokens.*` value or a named design-system token.
A literal does not re-theme: it survives a mode switch, an accent preset change,
and a density change unchanged.

Pass when:

- Colors come from `Tokens.*` — surfaces, `Foreground*`, `Border*`, or the
  semantic sets `Primary` / `Destructive` / `Warning` / `Success` / `Info`.
- Radii, spacing, and font metrics come from tokens
  (`SpacingXs..SpacingXl`, `RadiusSm/Md/Lg/Xl`, `RadiusButton`, `Cell*`).
- State-carrying property setters reject no-op writes, raise their changed event,
  and call `Invalidate()`; size-affecting ones also call `RequestHostLayout()`.
- Semantic hues are used for their defined meaning — `Success` for completed or
  valid, `Warning` for at-risk, `Destructive` for dangerous — never decoratively.

Fail when:

- Any literal color appears: `Color.FromArgb(...)`, a hex string, or a named
  `System.Drawing` color.
- Any literal pixel size, corner radius, duration, or font metric appears.
- The response claims the DRUI020 analyzer will catch a hardcoded literal in a
  consumer project. It will not — that analyzer is scoped to the framework's own
  assembly.
