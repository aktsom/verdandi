# M34: a SCREENSAVER setting (Windows and Linux), default OFF

Base: 6441ac2 (M33 green). Version 0.10.21. Lua only (`lua/core/screen.lua`, `lua/core/ui_settings.lua`, `lua/core/menu/ui.lua`); no C code.

## What exists (read in the code)

- `lua/core/screen.lua`: the screensaver is `metro[36]`, `time = 900`, `count = 1`. Its event clears the screen, updates it, sets `sleeping = true` and replaces `Screen.update` with an empty function. `Screen.ping()` (called on every key and encoder, `core/menu.lua`, `encoders.lua`, `keyboard.lua`) starts the timer and, when sleeping, restores `Screen.update`. `Screen.sleep()` calls the same event on purpose (a script, SYSTEM > SLEEP). The timer is only ever started by a ping.
- **The page the request calls SYSTEM > DISPLAY is not the page you see on Windows and Linux.** `core/menu/display.lua` (BRIGHTNESS, CONTRAST, GAMMA, saved in `system.display` for the oled chip) exists, but on a computer `core/menu/system.lua` lists `SCREEN >` (page id `UI`, `core/menu/ui.lua`) instead, with PRESET, COLOUR, BRIGHTNESS, CONTRAST, SAVE. DISPLAY is only reachable from SETTINGS, which the computer builds do not list. The place with brightness and contrast that the owner uses is SYSTEM > SCREEN, so the row goes there.
- SYSTEM > SCREEN keeps its values in `core/ui_settings.lua` (`ui.conf` in the norns home, key=value lines; "adding a setting: one entry in SETTINGS and one row in `core/menu/ui.lua`"). That is the settings store the Windows and Linux builds already use for this kind of setting. `ui.conf` is also read on macOS.

## What changes

- `Screen.set_auto_sleep(on)` (new). The automatic timer is only switchable on `NORNS_PLATFORM` windows and linux; on macOS and on the norns device it is ignored and the 15-minute screensaver stays exactly as it is.
  - On Windows and Linux the automatic timer starts OFF (the default). With OFF `Screen.ping()` does not start the timer, and if a timer event still arrives (a timer that was started before) it does nothing. `Screen.sleep()` still sleeps the screen on purpose and `Screen.ping()` still wakes it, as today.
  - OFF to ON starts the 15-minute timer at once (`screensaver:start()`). ON to OFF stops the timer and, if the screen is dark, wakes it at once (`Screen.update` is restored): the screen can never be left dark by the setting being OFF.
- `ui.conf`: a new key `screensaver=1` (ON) or `screensaver=0` (OFF); a missing key is OFF, so existing installs get OFF too. It is only written on Windows and Linux (the macOS file is not changed). `apply()` tells `screen.lua`.
- SYSTEM > SCREEN: one new row SCREENSAVER, after CONTRAST (so the colour presets' SAVE and DELETE stay together at the end), shown only on Windows and Linux. E3 changes it (right: ON, left: OFF), applied and saved at once like BRIGHTNESS and CONTRAST. The page already scrolls (five rows are visible, the strip of grey levels is below them), so the seventh row (eighth with DELETE) fits by scrolling; nothing else on the page is new.

## What stays

macOS (no row, 15 minutes, `ui.conf` not rewritten with the new key), the norns device, `Screen.sleep()`, SYSTEM > SLEEP, the DISPLAY page, all other rows.

## Tests (each shown to fail on the old code in `docs/port/phase-m34-without.txt`)

`linux/tests/screensaver_test.lua`: a fake timer (the real `core/metro` with a recording `_norns.metro_start/stop`; "time passes" by calling `_norns.metro(36, 1)` only for a metro that was started) and the real `screen.lua`:
- OFF by default with no saved value; saved to `ui.conf` and read back; a file without the key is OFF.
- OFF: ping starts no timer, a timer event leaves `Screen.update` the real one, the screen is never darkened; ON darkens after the time (event fires); `Screen.sleep()` works with OFF and ping wakes it; OFF to ON starts the timer; ON to OFF while dark wakes the screen and stops the timer.
- macOS and the device: the setting is ignored and the 15-minute timer works as before; `ui.conf` on macOS is not written with the key.
- The page: the SCREENSAVER row exists on Windows and Linux, not on macOS; E3 sets and saves; the text fits.
