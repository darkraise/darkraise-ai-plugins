The response must import from darkraise-ui's subpath entry points rather than the
package barrel. Subpath imports keep the bundle small, and some components are not
re-exported from the barrel at all.

Pass when:

- Imports take the form `darkraise-ui/components/<kebab-name>`, or a named subpath
  such as `darkraise-ui/theme`, `darkraise-ui/forms`, `darkraise-ui/layout`,
  `darkraise-ui/lib`.
- Component names match the kebab-case module they come from — `Button` from
  `darkraise-ui/components/button`, `Card` from `darkraise-ui/components/card`.

Fail when:

- Anything is imported from the bare `darkraise-ui` barrel.
- An import path is invented, such as `darkraise-ui/dist/...` or a chunk filename
  containing a build hash.
