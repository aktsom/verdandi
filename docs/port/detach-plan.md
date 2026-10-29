# Step 4: a detachable screen window (plan only; no product code is changed by this note)

Linux desktop build only (`NORNS_LINUX_DESKTOP`). Written from the code of this repository (read, not changed: `matron/src/platform/macos/sdl_bridge.cc`, `device_skin.c/.h`, `window_keys.c/.h`, `matron/src/platform/linux/desktop_shell_linux.cc`, `menu_skin.c`, `matron/src/hardware/screen/sdl.cc`, `lua/core/keyboard.lua`), plus three small measurements made for this plan (`docs/port/detach-measurements/`) and mock-up pictures (`docs/port/detach-previews/`, made over a real capture of today's window). **`macos/` is only read. The Mac build and the device build do not change: everything new is behind `NORNS_LINUX_DESKTOP`, in new Linux-only files or in `#ifdef` blocks that the Mac never compiles.** Nothing is built before the owner answers the questions in section 8.

"The box" is the main window (the device picture). "The screen" is the 128 x 64 OLED picture.

## 0. Summary and recommendation

- **What it is:** a second, ordinary SDL window that shows only the screen: the same live picture, through the same brightness, colour and contrast settings (it reads the very surface the main window draws from, so it cannot differ). No box around it. Freely resizable, fullscreen on a key, whole-number scales drawn with nearest neighbour, the in-between sizes with the same two-step rule the main window uses.
- **The keyboard works in it exactly as in the main window**, because keyboard events already do not depend on which window has the focus (section 1.4): the same mapping, the same F-keys, plus the window shortcuts Ctrl+O, Ctrl+Shift+S and Ctrl+Q, which today only work from the main window and will be made to work from both. The mouse over the picture does nothing (only window things: resize, move, fullscreen).
- **Detach / re-dock:** a small **SCREEN** button above the top right corner of the bezel in the main window, the key **F9** (works from both windows), and a menu item "Screen in its own window" (ticked while detached). While detached, the main window keeps every control and shows a dark placeholder with the sentence **"The screen is in its own window. Click here or press F9 to bring it back."**; a click on it, F9, or closing the screen window re-docks.
- **Closing the main window quits norns** (as it does today with a grid window open); the screen window goes with it, and its state is saved first.
- **State** (size, position, fullscreen, detached, frame on/off) in a small file of its own, `screen-window.conf` in the norns home, written by the C side; not in `ui.conf` (section 4.4 says why).
- **One measured finding that changes the drawing choice:** the main window's in-between scaling (`CAIRO_FILTER_BEST`) costs **70 to 320 ms per frame at 1366 to 2900 pixels wide** (it is cheap at the main window's usual size). A detached, resized or fullscreen screen window would stutter at 3 to 12 frames per second at in-between sizes. The same two-step rule with `CAIRO_FILTER_BILINEAR` costs **2.7 to 12 ms** and differs from `BEST` by **0.5 to 1.6 of 255 on average** (largest 31 to 34 on a one-pixel high-contrast edge). Whole-number scales (nearest) cost 1.3 to 12.6 ms at any size. Recommendation: nearest at whole scales (exactly as today), BILINEAR for the in-between sizes in the screen window, main window unchanged (section 3.2, question 8).
- **Everything that is not a window keeps working as it does now:** the virtual grid, arc and keys windows, real grids, arcs, crow and MIDI devices, screenshots and GIFs (they read the screen surface, never a window), the look settings (section 5).

## 1. How the windows are created, and how drawing and input are structured today

### 1.1 The windows

All SDL work happens on the **main thread**; norns itself (matron, Lua) runs on other threads and reaches the window through events and a small request queue (`bridge_event_type` / `bridge_req_t`, `bridge_call()`: from another thread it pushes an SDL event and waits until the main thread has done it; on the main thread it runs at once).

| window | created by | where | notes |
|---|---|---|---|
| **the main window ("the box")** | the screen backend `screen:sdl` (`hardware/screen/sdl.cc:180`) calls `sdl_bridge_create_window` -> `BRIDGE_CREATE_WINDOW` -> `bridge_do()` (`sdl_bridge.cc:385`) | 992 x 662 points (`SKIN_W + 2 * SKIN_MARGIN` by `SKIN_H + 2 * SKIN_MARGIN`), `SDL_WINDOW_RESIZABLE | ALLOW_HIGHDPI`, minimum half that size on Linux; `fit_main_window()` shrinks it if the display is smaller | stored in the static `the_window`; the title is `display_name(...)` ("Verdandi Linux") |
| **grid, arc, keys windows** | `toggle_grid()` / `toggle_arc()` / `toggle_keys()` (lines 975, 1134, 1426) -> `pane_open()` (line 655) | one SDL window each, `pane_t` (window + its own cairo canvas), titles "grid", "arc", "keys"; resizable; `arrange_windows()` (line 742) lays the open ones out around the main window and remembers the main window's place for when they close | opened from the box's buttons, the menu, **F6 / F7 / F8** (handled in Lua: `lua/core/keyboard.lua:225-230` call `_norns.grid_window(...)` -> `sdl_bridge_toggle_window` -> a device event to the main thread), or at start |
| **the file dialogs** | the shell (`file_picker.cc`) | a portal or zenity process, not an SDL window | unrelated |

Closing: `SDL_WINDOWEVENT_CLOSE` on a pane calls its `toggle_*` (so the window just closes); on the main window it posts `EVENT_QUIT` (`sdl_bridge.cc:2758`), which ends norns. `SDL_QUIT` does the same.

### 1.2 Drawing (software, no SDL renderer)

- The norns screen is drawn by the screen backend into a **128 x 64** surface (`priv->draw_surface`, `sdl.cc:189`); after every `screen.update()` the matron thread calls `sdl_bridge_present(window, surface)` (`sdl.cc:141`) and **waits** for the main thread.
- `present()` (line 342) copies it into the cairo surface **`oled`** (RGB24, grey) and, on Linux, `make_view()` makes **`oled_view`**: the same picture through the look tables (brightness, colour, contrast from SYSTEM > UI; `ui_look` event, code 3 in the toast event). **`oled_shown()`** returns whichever is current. `have_frame` is set, then `redraw(...)` and `gif_add_frame()` run.
- `redraw(full)` (line 302) draws into a cairo `canvas` the size of `SDL_GetWindowSurface(the_window)` and blits it with `SDL_UpdateWindowSurfaceRects`. `full` = the static layer (the box without the screen), `skin_draw_controls` (keys, knobs, buttons, toast), `draw_oled()` and the in-window menu; otherwise only the oled rectangle. `ensure_layers()` rebuilds the static layer when the size changes (`skin_geom`, `device_skin.c`).
- **The screen's size rule** (`device_skin.c:90-111`, Linux): scale `k = 4 * s`; if within 0.02 of a whole number `r` the rectangle is `128 r` wide and **drawn with `CAIRO_FILTER_NEAREST`** (`skin_draw_oled`, line 710); otherwise the width is an even number in between and the picture is **enlarged with nearest to a whole multiple `m = ceil(w / 128)` first and then scaled down with `CAIRO_FILTER_BEST`** (line 721-738). That is "the rule" the owner wants repeated.
- Grid, arc and keys windows each have `pane_begin()` / `pane_end()` (line 619, 644): a canvas the size of the window surface, drawn with their own skin file, blitted with `SDL_UpdateWindowSurface`. They are redrawn on `SDL_WINDOWEVENT_SIZE_CHANGED` / `EXPOSED` and when their state changes. **There is no shared "screen window" yet, and nothing in the code draws the screen anywhere but inside the box.**
- Toasts ("screenshot saved", "REC GIF", the standing audio/plug-in note) are a pill drawn by `skin_draw_controls` on the box (`device_skin.c:544`), at the right of the screen; timers clear them (`SDL_AddTimer`, `toast_event_type`).

### 1.3 Screenshots and GIFs

`save_screenshot()` (line 1797) paints `OLED_SHOWN()` four times as large with nearest and writes a PNG; `gif_add_frame()` (line 1855, called from `present()`) takes the 16 levels from `oled` and `gif_palette()` takes the colours from the look. **Neither reads a window**, so they cannot depend on which window shows the screen. Detached or docked, they produce the same bytes as long as `present()` keeps running for every frame (it must, section 3.2).

### 1.4 Input

- **Keyboard:** `SDL_KEYDOWN/UP` goes to `handle_key()` (line 2375). It only special-cases the **keys window** (`keys_typed`); for every other window it runs `window_keys_process` (the mapping in `window_keys.h`: `1 2 3` K1-K3, `Q W A S Z X` encoders, arrows, Enter/Space = K3, Esc/Backspace = K2; on Linux the launcher sets `NORNS_HARDWARE_KEYS=1`, so this is always on) and posts K/E events to matron or passes the key on as the norns USB keyboard (`shell_hid_keyboard_event`; Lua's `keyboard.lua` then handles **F1-F8**, text entry and scripts). **So a new window that is not the keys window already gets exactly the same keyboard behaviour; nothing has to be copied.** Window identity is not looked at, except in the two places below.
- **The in-window menu shortcuts** (`menu_event()` line 2117 -> `shell_menu_key`, `desktop_shell_linux.cc:283`): **F10** opens the menu, **Ctrl+O** imports, **Ctrl+Shift+S** screenshot, **Ctrl+Q** quit. `menu_event` **only accepts events whose `windowID` is the main window** (`ev->key.windowID != id` returns false), so these four keys do nothing when another window has the focus (true today for the grid window too).
- **Mouse:** `handle_button`, `handle_motion`, `handle_wheel` (lines 2236, 2309, 2347) use the **main window's `geom`** (`to_pixels()` converts with `geom.w / window width`, line 2104) and call the box's hit test (`skin_hit`: K1-K3, E1-E3, the button row, the oled on the MIX page). The event loop sends events of the three panes to their own handlers first (`is_pane(...)`, lines 2691-2735) and everything else to these. **A mouse event of a new window must be routed away before it reaches them**, or it would be converted with the wrong geometry.
- **Drops:** `SDL_DROPFILE` has no window test: a file dropped on any window is imported.
- **Devices:** real grids, arcs, crow and MIDI devices come in through the device monitor, libmonome and ALSA/JACK threads (`dev_list`, `device_monitor`, `midi_autoconnect`), **not through windows**. The virtual grid/arc are ptys that libmonome opens like USB devices (`vgrid_*`); their windows only draw and click. Nothing about a screen window touches any of it.

## 2. What the owner asked for, as requirements

1. A second window with only the screen; live; same look settings; no box; freely resizable; fullscreen toggle; crisp scaling by the main window's rule.
2. Remembers size, position, fullscreen between starts; defaults and a fallback for a damaged file.
3. Keys and encoders from the computer keyboard exactly as in the main window, including shortcuts that make sense; the mouse only for the window itself.
4. Grid, arc and keys windows, real devices and MIDI unaffected, whichever window is detached or hidden.
5. A dark placeholder with one plain sentence while detached; activating it re-docks. A proposed way to detach and the keys; what happens on closing either window.
6. Screenshots and GIFs the same in both modes.

## 3. Proposed design

### 3.1 Detach, re-dock, the placeholder (pictures: `docs/port/detach-previews/overview.png`, `docked-with-button.png`, `detached-main-window.png`, `screen-window.png`)

- **Three ways, all doing the same toggle** (one function, `screen_window_toggle()`):
  1. **A button "SCREEN" with the arrow glyph** the MAIDEN/MANUAL buttons use, **70 x 30 units at x 522..592, y 262..292**, just above the bezel's top right corner. I checked the free space on today's window: that band right of E1 and above the bezel is empty (picture 1). It is a new control id (`SKIN_SCREEN`, appended after `SKIN_MUTE` inside the Linux enum; no existing value changes). The page buttons keep their places; the top row is full and is not touched. It is lit while the screen is out.
  2. **The key F9**, handled in C (not in Lua), from the main and the screen window. Reason: F6-F8 go through Lua (`keyboard.lua`) and therefore do nothing while a text entry or a menu has the keyboard (`te_kbd_cb.code` is checked first); a re-dock key must always work. Every F-key is in `keyboard.lua`'s table (F9, F11 and F12 too: a script can read them today); F1-F8 and F10 are already taken from scripts, so F9 and F11 would be two more (question 2). No F-key is free of that, so the choice is only which two.
  3. **A menu item "Screen in its own window"** in the right-click menu (a ticked item like "Copy samples into dust", hint "F9"), placed after "Virtual keyboard".
  The placeholder and the screen window's own close button re-dock too.
- **The placeholder:** while detached, `draw_oled()` in the main window paints the screen rectangle (the bezel interior: `bezel_x..bezel_x + bezel_w`) in the dark grey of the bezel (`#16171a`) with the sentence in two centred lines in the box's grey text (about 17 units high, `Helvetica Neue` with the same fallback as the toasts): **"The screen is in its own window." / "Click here or press F9 to bring it back."** It is hit-tested like a button (`skin_in_bezel`, new, Linux only): press and release on it re-docks, the hand cursor shows; while detached the MIX page's mouse-on-screen is off (the placeholder owns that rectangle). Redrawing it needs only a full redraw of the box when the state changes; later frames are **not** drawn into the main window (saves the work: see 3.2).
- **Toasts** stay on the box, and are also drawn as the same pill, small, at the bottom of the screen window (the screenshot confirmation and "REC GIF" are the things one needs to see when the box is hidden; question 7).

### 3.2 The screen window

- **Creation** (main thread, from `screen_window_toggle()` / at start from the saved state): `SDL_CreateWindow("screen", x, y, w, h, SDL_WINDOW_SHOWN | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_RESIZABLE)`, minimum size 256 x 128 points (2 x), the app icon (`set_icon`), `SDL_SetWindowFullscreen(..., SDL_WINDOW_FULLSCREEN_DESKTOP)` when saved as fullscreen (desktop resolution: no mode change, no flicker, works with any WM; I checked that SDL 2.30 does it under Xvfb with no window manager, `detach-measurements/sdl_fullscreen_xvfb.c`). Title **"screen"**, like "grid", "arc", "keys". It is a `pane_t`-style window (its own cairo canvas via `pane_begin/pane_end`), so no new drawing infrastructure is needed.
- **Drawing:** a new `screen_window_draw(cr, w, h, oled_shown())` (new file `matron/src/platform/linux/screen_window.cc`; the geometry rule in `screen_window_geom.c`, pure C): black background; `k = min(w / 128, h / 64)` in surface pixels; if `|k - round(k)| <= 0.02` (and `round(k) >= 1`) the picture is `128 round(k)` wide, nearest; otherwise an even width `2 floor(32 k)` that fits, drawn by the same two-step rule (nearest to a whole multiple, then scaled), **centred**, black bars at the sides or top and bottom. Free resizing therefore gives letterboxing, not distortion; the aspect ratio cannot be locked on every desktop (SDL has no portable aspect lock), so the bars are the honest way.
- **Cost, measured** (`detach-measurements/screen_cost.c`, cairo calls identical to `skin_draw_oled`, 4 cores here, per frame, including the copy to the window surface):

  | window | scale | nearest/whole | in-between with `BEST` (today's rule) | in-between with `BILINEAR` |
  |---|---|---|---|---|
  | 1024 x 512 | 8x whole | 1.3 ms | - | - |
  | 1920 x 1080 fullscreen | 15x whole | 4.3 ms | - | - |
  | 2560 x 1440 | 20x whole | 5.3 ms | - | - |
  | 3840 x 2160 | 30x whole | 12.6 ms | - | - |
  | 1500 x 800 | 11.7x | - | **89 ms** | 3.6 ms |
  | 1366 x 768 fullscreen | 10.7x | - | **82 ms** | 2.7 ms |
  | 3440 x 1440 fullscreen | 22.5x of the height | - | **314 ms** | 12.4 ms |

  Difference between the two filters on a test pattern (`filter_diff.c`, same nearest enlargement first): mean 1.64 / 1.48 / 1.06 / 1.01 / 0.79 / 0.55 of 255 at 700 / 1000 / 1366 / 1500 / 1700 / 2900 pixels wide, largest 31 to 34 (a one-pixel black-white edge). So `BEST` is fine for the box (small) and unusable for a big free window; `BILINEAR` is visually the same to within a grey step on average. **Recommendation: whole scales exactly as in the box; in-between sizes with BILINEAR in the screen window; the box is not changed** (a later step could make the box use the same function; question 8). I will make before/after pictures of both filters at the sizes the owner uses before the filter is final.
- **Pacing:** `present()` stays the single entry for every frame and always converts `oled`, makes `oled_view`, and feeds the GIF; after that it draws **either** the box (docked: as today) **or** the screen window (detached: the box is not redrawn per frame). The wait of the matron thread is therefore the same as today, plus nothing when docked.
- **The look:** a `ui_look` event (code 3) already calls `make_view()` and `redraw(false)`; it will also redraw the screen window. Same surface, same tables: identical colours by construction (the test compares pixels, section 6).
- **Frame:** the normal title bar of the desktop by default (movable, resizable, closable on every desktop, including ones whose hit-test support I cannot test here). The owner's "no decoration" may mean the box only or the frame as well; so **`Shift+F11` toggles a borderless window** (`SDL_SetWindowBordered`): then `SDL_SetWindowHitTest` makes the interior draggable (move) and an 8-pixel edge resizable, and a double click is not available (the drag area swallows it; F11 still works). Saved as `border=0|1`. Needs a real window manager to try (checklist). Question 1.
- **Fullscreen:** **F11** from the screen window (and a double click on the picture when the frame is on), `SDL_WINDOW_FULLSCREEN_DESKTOP` on the display it is on; the cursor hides after 2 s without movement and comes back on motion; leaving restores the previous size and position (kept in the state: SDL reports the fullscreen size otherwise). F11 in the main window does nothing there and is not forwarded to scripts (so, like F9, a script loses it on the Linux desktop).

### 3.3 Input routing (what changes in `sdl_bridge.cc`, all in `#ifdef NORNS_LINUX_DESKTOP` blocks)

| event | screen window | main window | other windows |
|---|---|---|---|
| keyboard | the same path (`handle_key`: nothing special for it); plus two early shortcuts: F9, F11, Shift+F11 | as today, plus F9 | as today |
| Ctrl+O, Ctrl+Shift+S, Ctrl+Q | `menu_event` accepts key events of the screen window for these three (menu closed) | as today | grid/arc/keys: unchanged (they did not have them) |
| F10 | brings the box to the front and opens its menu there (`SDL_RaiseWindow`), so every menu item stays reachable from the keyboard; the menu is **not** drawn over the small screen window (it needs about 450 pixels of height) | as today | - |
| mouse button/motion/wheel | routed to `screen_window_mouse()`: window-only actions (double click = fullscreen when framed, borderless drag); **never** to `handle_button/motion/wheel` | as today (+ the SCREEN button and the placeholder) | their own handlers |
| right button | nothing (no menu on the screen window; the desktop's own frame menu stays) | menu, as today | - |
| drop | import (unchanged: no window test) | import | import |
| close (`SDL_WINDOWEVENT_CLOSE`) | **re-dock** (the same as F9) | **quit norns** (as today) | toggle the pane |
| size/move/exposed | redraw; save the state after 500 ms without further change | as today | as today |
| focus lost | nothing | nothing | the keys window releases typed notes (unchanged) |

Two small details: `WK_MODE` changes the title of the window that had the key (norns mode); for the screen window the title change is skipped (it keeps "screen"). The text-entry and menu pages of norns need no change: they run in Lua and draw into the same 128 x 64 picture.

### 3.4 The other windows and devices

- **grid, arc, keys:** untouched; their toggles, layout and focus handling do not look at the screen window. `arrange_windows()` keeps arranging the box and those three; **the screen window is not part of that layout** (it opens at its saved place, or beside the box on first use: right of the box if the display has room, else below, else centred), so opening a grid window never moves it. If it overlaps one of them the owner moves it; the saved place wins.
- **Hidden or minimised screen window, or box:** the pane windows and all devices keep working: they are driven by their own events and by threads, not by the other windows. A minimised box does not stop `present()` (the screen window, or nothing, is drawn).
- **Real grids, arcs, crow, MIDI:** unchanged by construction (section 1.4: they do not pass through any window). The existing device tests stay in `run_all.sh`; a new window scenario opens the virtual grid while the screen is detached and presses a cell (section 6).
- **GIF and screenshot:** as section 1.3: the same code in both modes; the test compares the files.

### 3.5 Closing

- **The screen window's close button** (or Alt+F4, or the compositor's close) **re-docks**: the window is destroyed, its geometry and `detached=0` are saved, the box shows the screen again. This matches the grid/arc/keys windows (closing one just closes it) and can never leave norns without a visible screen.
- **The box's close button quits norns** (as it does today, with or without grid windows open). With the screen window open it goes down with it, after saving the state including `detached=1`, so the next start opens detached again (question 3). Reasons not to keep the screen window alive without the box: the box carries the MIC/MUTE/GRID/ARC/KEYS/MAIDEN/MANUAL buttons and the audio status note, so a running norns without it has no visible controls except the keyboard; and "close = quit" must stay one rule for every window combination (Ctrl+Q from the screen window quits too). If the owner wants a "screen only" way of working, **minimising the box** (or leaving it behind the screen window) gives it without a new mode.

## 4. State file

### 4.1 Where

`<norns home>/screen-window.conf` (the C side reads `HOME`, which the launcher sets to the norns home, like `dust_dir()`). Plain `key=value` lines like `audio.conf` and `ui.conf`:

```
detached=1
x=1480
y=120
w=1024
h=512
fullscreen=0
border=1
```

Written through a temporary file and renamed, 500 ms after the last change of size, position, fullscreen, frame or detached state, and once more at quit. `x y w h` are the **windowed** rectangle (the pre-fullscreen one while fullscreen), in points.

### 4.2 Defaults

Missing file or missing keys: `detached=0`, `fullscreen=0`, `border=1`; size 640 x 320 (5 x) if the display's usable area fits it, else the largest whole multiple that fits (never below 256 x 128); position beside the box (3.4).

### 4.3 Damaged or stale values (log line on stderr, i.e. `logs/norns.log`, in `ui.conf`'s style: `screen-window.conf: w='abc' is not a size, using 640`)

- not an integer, out of range (`w`, `h` 128..16384; `x`, `y` -32768..32768; flags 0 or 1), unknown key, a line without `=`: that value falls back to its default and a line says so; the rest of the file is used;
- a rectangle that does not show at least 64 x 64 pixels on any display (a monitor that is no longer there, or a resolution change): position and size reset to the defaults on the box's display;
- the file is never required; a read error is the same as "missing".
- Wayland compositors may ignore a requested position; then the size is restored and the position is the compositor's (checklist).

### 4.4 Why not `ui.conf`

`ui.conf` is read and written by Lua (`core/ui_settings.lua`) on every UI change; it keeps lines it does not know, logs "unknown key ignored" for each at every start, and rewrites the whole file. A second writer in C (on every window move) would race with it and clutter its log. A separate file has one writer, never produces a Lua log line, and can be deleted without touching the look settings. **Related edits when it is built:** `linux/tidy.sh` (the list of names `disable` refuses to move: `ui.conf` is there; `screen-window.conf` joins it), the CLEAN UP page text, the manual's file table (section 9) and `docs/port/RUN-ON-LAPTOP.md`. `tidy flatten` moves it like any other top-level file (no change).

## 5. Interplay with the look and other settings (checked in the code)

- **Brightness, colour, contrast (SYSTEM > UI):** the screen window draws `oled_shown()`; `ui_look` events rebuild it and redraw both windows. No second copy of the tables.
- **"Open the file dialog when a script loads a file", Copy samples, input choice:** menu items, unrelated; the menu stays in the box.
- **Display name / title:** "screen" for the window; the main window keeps "Verdandi Linux" (the window tests find the box by that name; a test that detaches finds the second window by "screen").
- **MIX page mouse on the screen** (the mouse drag on the MIX page levels, `drag_oled`) works only on the box's screen; the owner said clicks over the picture need not act. While detached the placeholder owns that rectangle.

## 6. Tests (written first, each shown failing before it is built)

- **Pure C, no SDL, like `device_skin_linux_test.c`** (registered in `run_all.sh`): `screen_window_geom_test.c` (window size to picture rectangle: whole scales within 0.02 give `128 r` with nearest, in-between sizes give an even width that fits and is centred, tiny and huge windows, 2:1 and other aspects, the hit rectangle) and `screen_window_conf_test.c` (parse: defaults, every damaged value in 4.3 with its log line, an off-screen rectangle, round trip write/read, the atomic rename, unknown keys).
- **Window scenario under Xvfb** (`probe_detach.lua`, xdotool, a stub zenity as in the dialog scenario): (1) default start: one window; (2) F9: a second window named "screen" exists and the box shows the placeholder (the screen rectangle is the placeholder grey, not the script's picture); (3) the picture in the screen window equals the box's picture for a known script (pixel compare at a whole scale: `window_probe.lua`'s white rectangle); (4) `ui.conf` yellow/0.4: the same level has the same colour in both windows (the technique of `ui_look_scenario`); (5) resize by `xdotool windowsize` to a whole scale (nearest: block interiors uniform, edges at multiples) and to an in-between size (the centre pixel of every block equals the source level; no row or column is blurred beyond the edge pixels); letterboxing when the aspect changes; (6) keyboard in the screen window: `1`, `2`, `3`, `Q`, arrows reach the script's `key`/`enc` handlers exactly as in the box (a probe prints them), F6 opens the virtual grid and a cell press reaches the script while detached, Ctrl+Shift+S makes the same PNG as docked, a GIF is recorded (same frame count and palette as docked), Ctrl+O reaches the import (stub zenity), Ctrl+Q quits; (7) F11 makes the window the display size and back to the saved size; (8) close the screen window: it re-docks, the placeholder is gone, one window left; (9) detach again, quit with Ctrl+Q, start again: it comes back detached with the same size, and a `screen-window.conf` with damaged values starts with defaults and a log line; (10) the box's close button ends norns even with the screen window open; (11) a hidden (unmapped) screen window or box: the virtual grid and the MIDI test device still work (the existing probes run once with the screen detached).
- **Existing tests that must stay green:** every existing `run_all.sh` window test (the screen starts docked: no change), `device_skin_linux_test.c` (the new control id and `skin_in_bezel` are tested there too), the Mac tests under `macos/tests` (they compile the shared files without the Linux define).
- **Cannot be tested here (added to `HARDWARE-CHECKLIST.md` when built):** the window frame, move and resize on the owner's real desktop (there is no window manager in this container: Xvfb only), double click and cursor hiding, **borderless drag/resize** (`SDL_SetWindowHitTest` on his compositor), fullscreen on several monitors and across a resolution change, high-DPI and fractional scaling on Mint, a Wayland session (positions are not restored there), the saved position on a second monitor that is later unplugged, and how the in-between sizes look to his eye (the filter choice).

## 7. Order of work and size

1. **4a, no behaviour change:** `screen_window_geom.c`, `screen_window_conf.c` (+ unit tests, registered), the placeholder and button drawing and `skin_in_bezel` in `device_skin.c` (Linux only), pictures from the real renderer. About 300 lines.
2. **4b, the window:** creation, drawing, re-dock, close rules, persistence, the button, F9, the menu item, the placeholder, `present()` routing; scenario steps 1-4, 8-10. About 350 lines in `sdl_bridge.cc` (inside `#ifdef`) and `screen_window.cc`.
3. **4c, input and fullscreen:** event routing, shortcuts, F10, F11, Shift+F11 and the borderless mode, the cursor, the toast pill; scenario steps 5-7 and 11. About 200 lines.
4. **4d:** manual, RUN-ON-LAPTOP, HARDWARE-CHECKLIST, `tidy.sh` protected name, STATUS; `run_all.sh`; push.

After each of 4a-4c: build, `run_all.sh`, push.

## 8. Questions for the owner (answer in the chat; nothing is built before)

1. **Frame:** normal title bar by default and `Shift+F11` for borderless (my recommendation: always movable and resizable, borderless is one key away), or borderless by default?
2. **Keys:** F9 = detach / re-dock, F11 = fullscreen, Shift+F11 = frame on/off. Every F-key can be read by scripts today (F1-F8 and F10 are already taken from them), so any choice costs scripts a key; F9 sits next to F6-F8 and F10. OK, or other keys (for example Ctrl+Shift+D and Ctrl+Shift+F, which no script uses)?
3. **Remember "detached" between starts** (my recommendation: yes; the box then shows the placeholder at start), or always start docked and remember only size and position?
4. **Closing the box quits norns** (my recommendation), or should a detached screen keep running without the box?
5. **F10 in the screen window** raises the box and opens its menu there (my recommendation), or nothing?
6. **The SCREEN button above the bezel's top right** (picture `docked-with-button.png`), or only the menu item and F9 (no new button)?
7. **Toast pill in the screen window** (screenshot saved, REC GIF): yes (my recommendation) or only in the box?
8. **In-between scaling in the screen window: BILINEAR** (fast; mean difference to today's filter about 1 of 255) or the same `BEST` as the box (identical but 80 to 300 ms per frame at large sizes)? And should the box also move to the fast filter later?
9. **Title "screen"** like grid, arc, keys, or "Verdandi screen"?
10. **Whole-scale snapping:** free resizing gives black bars at other shapes and slightly softer in-between scales. A later key that jumps the window to the nearest whole scale (for example 8x = 1024 x 512) is easy; wanted for the wishlist?

## 9. Risks

- **Event routing:** every mouse handler that uses the box's geometry must be reached by box events only; the table in 3.3 is the checklist and the test (11) covers a click in the screen window not producing a K/E event.
- **`menu_event` and focus:** today it ignores other windows; opening the box's menu from the screen window raises another window, which some compositors refuse (focus-stealing prevention): then F10 opens the menu without raising (the box may stay behind). Noted for the checklist.
- **No window manager here:** frame, borderless and focus behaviour are verified only on the owner's desktop; the code path that does not depend on a window manager (fullscreen through SDL, resizing through X) is tested.
- **Wayland:** window positions are not restorable; hit-test dragging of a borderless window depends on the SDL version and compositor.
- **Shared file:** `sdl_bridge.cc` is compiled by the Mac too; every edit is inside `#ifdef NORNS_LINUX_DESKTOP` or in new Linux-only files (`matron/src/platform/linux/`, added to `norns/wscript` next to `menu_skin.c`), and the Mac unit tests build the shared files without the define. I cannot build the Mac app here; I will re-read each shared hunk against that rule.
- **Frame cost** when docked is unchanged; detached, the box is not redrawn per frame, so the total work is about the same as today.
