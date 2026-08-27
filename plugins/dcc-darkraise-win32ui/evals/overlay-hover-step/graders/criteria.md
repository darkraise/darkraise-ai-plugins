A hover fill must be at least one *visible* surface step above its host surface.
A menu or dropdown list sits on `SurfaceOverlay`, so its hover fill must be
`Surface3`.

Pass when:

- The hover fill on the overlay-hosted item is `Tokens.Surface3`.
- The reasoning names the host surface, not just the next number in the sequence.

Fail when:

- The hover fill is `Surface2`. On a `SurfaceOverlay` host this is nearly identical
  to the surface in dark mode and reads as no feedback at all — the item looks
  unresponsive, and the code looks reasonable, which is why this must be caught.
- The hover fill is a literal color.
- Hover changes geometry rather than only fill, border, and foreground color.
