# Linux desktop

**Status:** unverified — no session has run this guide yet. The first run replaces this line with the date and what ran.

- **Launch:** `Xvfb :99 -screen 0 1440x900x24 &` (note its PID), then the app
  with `DISPLAY=:99` as a background task. GTK, Qt and Tauri apps all run
  this way.
- **Drive:** `xdotool` (`search --name`, `windowactivate`, `key Tab`,
  `key Return`, `key Escape`, `type`, `mousemove` and `click`).
- **Screenshots:** `import -display :99 -window root <file>` (ImageMagick) or
  `xwd -root -display :99 | convert xwd:- <file>`.
- **Themes:** `GTK_THEME=Adwaita:dark` for GTK, `QT_QPA_PLATFORMTHEME` or the
  app's own setting for Qt.
- **Accessibility:** the AT-SPI tree (`python3` with `pyatspi`, or
  Accerciser) for names, roles and focus.
- **Clean up:** kill the app, then Xvfb.
