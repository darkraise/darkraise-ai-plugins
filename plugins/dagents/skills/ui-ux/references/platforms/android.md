# Android

**Status:** unverified — no session has run this guide yet. Never edit this file, which ships with the plugin; the proof report's `## Automated checks` records that the guide was unverified and which of its steps ran.

- **Launch:** `emulator -avd <name> -no-window -no-audio &` (note its PID),
  `adb wait-for-device`, then `adb install -r <apk>` and
  `adb shell am start -n <package>/<activity>`.
- **Drive:** `adb shell input tap <x> <y>`, `input text <text>`,
  `input keyevent 61` (Tab), `66` (Enter), `111` (Escape).
- **Screenshots:** `adb exec-out screencap -p > <file>`.
- **Themes and text size:** `adb shell cmd uimode night yes|no`;
  `adb shell settings put system font_scale 1.3` for large text.
- **Accessibility:** `adb shell uiautomator dump` and read the XML for
  `content-desc`, `focusable` and `focused`.
- **Clean up:** `adb emu kill`, then confirm the emulator PID is gone.
