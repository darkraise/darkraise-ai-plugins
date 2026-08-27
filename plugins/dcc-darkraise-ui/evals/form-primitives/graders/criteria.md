The response must use the field primitives from `darkraise-ui/forms`, which
already wrap `Field` with correct label, description, error, and ARIA wiring.

Pass when:

- `TextField` (and any other needed primitive) is imported from
  `darkraise-ui/forms`.
- Validation is expressed through the `isInvalid` and `errors` props.
- `errors` is an array of objects with a `message` property — the type is
  `Array<{ message?: string } | undefined>`. An array of bare strings is wrong.
- `onChange` receives the value directly, not a change event.
- Submit and cancel use `FormActions` rather than a hand-built button row.

Fail when:

- The form is assembled from raw `div` + `Label` + `Input`.
- The error is rendered as a hand-written element such as
  `<p className="text-red-500">`.
- An invalid state is signalled by a manual red border utility.
- `errors` is passed an array of plain strings.
