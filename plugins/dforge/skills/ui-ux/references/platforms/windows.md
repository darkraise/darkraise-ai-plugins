# Windows desktop

**Status:** unverified — no session has run this guide yet. The first run on a Windows host replaces this line with the date and what ran.

- **Launch:** the profile's Harness command, or the built executable, as a
  background process; note its PID and kill its tree with
  `taskkill /F /T /PID <pid>` when done.
- **Drive:** the project's own harness when it has one (for example a
  GuiVerify-style check runner); otherwise UI Automation through FlaUI (C#) or
  pywinauto (Python): find elements by AutomationId, invoke, type, and send
  `{TAB}`, `{ENTER}` and `{ESC}` for the keyboard walk.
- **Screenshots:** the harness's capture, FlaUI `Capture.Element`, or
  pywinauto `capture_as_image()`, saved by absolute path into the evidence
  directory.
- **Themes and scale:** light and dark app mode, a high-contrast theme, and
  display scale 100% and 150%.
- **Accessibility:** the UI Automation tree gives each control's Name,
  ControlType and keyboard focus; an unnamed focusable control is a finding.
- Runs only on a Windows host; elsewhere the items are `unverifiable`.
