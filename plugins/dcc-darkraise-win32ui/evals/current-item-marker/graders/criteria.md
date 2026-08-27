"You are here" uses the framework's single current-item marker, in the idiom of the
surface it appears on, always carrying at least two signals so it never rides on
color alone.

Pass when:

- A rectangular nav item's active state uses `SelectionFill` (Primary at 14% alpha)
  **plus** a 1px `Primary` border, with a heavier label weight and a `Primary`
  icon — the fill alone is never the marker.
- Selection change clears the old item's marker and paints the new one, cross-fading
  at about 90ms.
- `SelectionFill` is treated as a named token composited at 14% alpha over the host
  surface, not a pre-blended constant.

Fail when:

- An accent bar, rail, or indicator animates or slides between siblings.
- A dot, chevron, or other invented marker is introduced.
- The active state is signalled by color alone, with no border or weight change.
- A pre-blended `lerp(surface, accent, 0.14)` constant is used, which accent presets
  and light/dark switches would miss.
