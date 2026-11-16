# Web

**Status:** verified 2026-10-24 on Linux with Playwright MCP (the probe in the spec's riskiest assumption).

- **Launch:** the profile's Harness command (a dev server) as a background
  task; wait for its URL to answer (`curl -s -o /dev/null -w '%{http_code}'`).
  Electron apps run through the project's Playwright runner with Playwright's
  Electron support.
- **Drive:** Playwright MCP. Load the `mcp__playwright__*` tools with
  ToolSearch: `browser_navigate`, `browser_resize` (each viewport),
  `browser_click`, `browser_type`, `browser_press_key` (`Tab`, `Shift+Tab`,
  `Enter`, `Escape`, arrows for the keyboard walk), `browser_snapshot` (the
  accessibility tree: names, roles and the `[active]` focus marker),
  `browser_take_screenshot`, `browser_close`.
- **Themes:** `browser_run_code_unsafe` with
  `await page.emulateMedia({ colorScheme: 'dark' })`, or the app's own theme
  switch; reduced motion with `emulateMedia({ reducedMotion: 'reduce' })`.
- **Force states:** `browser_run_code_unsafe` with `page.route` to delay,
  fail (`route.fulfill({ status: 500 })`), empty or enlarge responses, then
  reload.
- **Automated checks:** `browser_console_messages` for errors; overflow with
  `browser_evaluate` of
  `document.documentElement.scrollWidth > document.documentElement.clientWidth`;
  an axe scan when the project has `axe-core` installed (`page.addScriptTag`
  with its `axe.min.js`, then `axe.run()`), otherwise record the scan as not
  run in `## Automated checks`.
- **UI test runner:** when the profile names one (for example
  `npx playwright test`), `test`-tagged statements run there, and their test
  names are evidence.
