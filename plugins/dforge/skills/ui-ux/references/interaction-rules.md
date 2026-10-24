# Interaction rules

Checkable defaults for every control and flow in a UI/UX contract. The
contract may override a rule with its reason; the proof report then cites that
reason on the deviation row. Sources: the Vercel Web Interface Guidelines,
WCAG 2.2 AA, Nielsen's usability heuristics, and the copy guidance of
Anthropic's frontend-design skill.

## Feedback and latency

- Every action responds within 100 ms: a pressed state, a pending state or
  the result.
- A pending indicator waits 150-300 ms before it shows and stays at least
  300-500 ms once shown, so fast responses do not flicker.
- A button that starts work stays enabled until the request starts, then
  shows its pending state and cannot submit twice.
- An optimistic update that the server refuses rolls back visibly, with the
  reason.
- Success is confirmed where the user is looking; a confirmation names the
  action in the past tense ("Published" for "Publish").

## Forms

- Every input has a visible label; a placeholder is never the label.
- Validation runs on blur or on submit, not on every keystroke before the
  first blur.
- On submit, focus moves to the first invalid field.
- An error sits next to its field, is tied to it for assistive technology,
  and says what is wrong and how to fix it.
- Input survives an error, a failed request and a back navigation.
- Paste is never blocked; input types and autocomplete match the data.
- Leaving with unsaved changes asks first.

## Focus and keyboard

- Every action is reachable and operable by keyboard alone, in visual order.
- Focus is always visible.
- A dialog moves focus inside when it opens, keeps it there while open,
  closes on Escape and returns focus to its trigger.
- After a deletion, focus moves to the next sensible element, never to the
  top of the page.

## Navigation and state

- Filters, tabs, pagination, sort and open panels live in the URL or the
  platform's restorable state, so reload, back and share keep them.
- Back returns to the previous view with its scroll position and state.
- Links navigate; buttons act.

## Destructive actions

- A destructive action names what it destroys ("Delete 3 files?") and its
  buttons name the outcomes ("Delete files", "Keep files").
- Prefer undo to a confirmation for reversible actions.

## Copy

- Name things by what the user understands, not by how the system is built.
- An action keeps one name through the whole flow.
- Errors say what happened and how to fix it, without apology or vagueness.
- An empty state says what belongs there and offers one next action.
- Sentence case, no filler; numbers, dates and currencies formatted for the
  locale.

## Responsive and touch

- Each breakpoint states what changes (navigation collapses, a table becomes
  a list), not only what shrinks.
- Touch targets are at least 44 x 44 px; never below WCAG 2.2's 24 x 24 px.
- No horizontal scroll at the narrowest viewport outside content meant to
  scroll.
- Every hover-only affordance has a touch and a keyboard equivalent.
- Content respects safe areas on devices with notches.

## Motion

- Motion explains a change (opening, moving, confirming); decoration is rare.
- Animate transform and opacity, not layout properties; never
  `transition: all`.
- Feedback motion lasts 150-300 ms and can be interrupted.
- The reduced-motion setting replaces movement with a fade or with nothing.

## Accessibility

- Text contrast at least 4.5:1, large text and UI components at least 3:1,
  in every theme.
- State is never conveyed by colour alone.
- Every control has an accessible name; icon-only buttons have a label.
- Status changes (saved, failed, results loaded) are announced to assistive
  technology.
- Zoom to 200% keeps the content usable; the viewport never disables zoom.

## Performance

- The contract states numeric budgets; on the web the defaults are LCP under
  2.5 s, INP under 200 ms and CLS under 0.1.
- Lists longer than the contract's threshold are virtualized or paginated.
- Images reserve their dimensions, so loading does not shift layout.

## Internationalization and theming

- No text in images; strings come from the project's string resources when
  it has them.
- Layouts survive strings 30% longer and right-to-left text.
- Every theme the profile names is proven, high contrast included where the
  platform has it.
