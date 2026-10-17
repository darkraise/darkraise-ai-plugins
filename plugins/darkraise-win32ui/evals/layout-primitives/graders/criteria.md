Layout comes from the framework's layout primitives. Containers own spacing;
children never position themselves.

Pass when:

- Structure uses `Stack`, `Inline`, `Grid`, `GridPanel`, `DockPanel`, `WrapPanel`,
  or `UniformGrid` as appropriate.
- Gaps come from a container's spacing parameter using a `Spacing*` token, not from
  a `Spacer` inserted between every pair.
- Any content that could exceed its region is wrapped in a `ScrollViewer` — the only
  sanctioned answer to real overflow.

Fail when:

- Children are positioned by setting `X` / `Y` or absolute bounds.
- Type is shrunk below the scale, or padding cut below the tokens, to make content
  fit.
- The response relies on children shrinking to fit. No layout manager compresses
  children when space is tight — they overflow, and clipping is the backstop.
- `Stack.Wrap` or `Grid.Responsive` is used for wrapping. Both are inert stubs;
  wrapping is `WrapPanel` only.
