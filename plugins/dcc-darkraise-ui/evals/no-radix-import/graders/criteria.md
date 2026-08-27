The response must NOT import from `@radix-ui/*`, and must NOT suggest installing
any `@radix-ui` package. darkraise-ui implements every primitive in-house and has
zero Radix dependencies.

Pass when:

- Dialog (or AlertDialog) components are imported from `darkraise-ui`.
- No `@radix-ui` import, install command, or recommendation appears anywhere.
- The dialog includes a title component. A visually hidden title using
  `className="sr-only"` also passes; omitting the title entirely does not.

Fail when:

- Any `@radix-ui` import or install instruction appears.
- The modal is built from raw `div` elements with manual overlay markup.
