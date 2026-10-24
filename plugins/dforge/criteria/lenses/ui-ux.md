# UI/UX Lens - Review Criteria

Applies: ui-paths

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:ui-ux] at your own severity.

## Ground Truth Note

Judge the UI the user will meet, not the main path the diff was written for.
When the plan's spec has a "## UI/UX contract", read it first: an item the
diff should build and does not is a finding. scripts/ui-lint findings already
reach the implementer; look for what a single-line pattern cannot see.

## Criteria

### Missing States {#states}

Look at every component, screen and data fetch the diff adds or changes.
Report a finding when a data state (loading, empty, error, partial, offline,
permission denied, very long or very large content) or a control state
(hover, keyboard focus, active, disabled, pending, invalid) has no rendering,
or when a pending action can be submitted twice.

### Keyboard and Assistive Access {#access}

Look at interactive elements, dialogs, menus and custom controls. Report a
finding for an action reachable only by pointer, a control without an
accessible name, focus that is lost or not returned after a dialog closes or
an item is deleted, a focus trap with no exit, motion without a
reduced-motion fallback, or state conveyed by colour alone.

### Design System Bypass {#tokens}

Look at styles, class names and component choices. Report a finding for a
raw colour, size or spacing value where the design system has a token, a
hand-built control where the design system has a component, or a variant
built from overrides instead of the component's own variant.

### Feedback and Forms {#feedback}

Look at forms, buttons that start work, and destructive actions. Report a
finding when validation fires at the wrong time or never, an error does not
say what happened and how to fix it, input is lost after an error, a slow
action shows no progress, or a destructive action has neither a confirmation
naming what it destroys nor an undo.
