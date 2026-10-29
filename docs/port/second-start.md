# Starting Verdandi a second time: bring the running window to the front

Linux desktop build only (`NORNS_LINUX_DESKTOP`). The first start is unchanged. `macos/` was not touched.

## How "already running" was detected before

`linux/norns.sh` ran `pgrep -x norns` at the end of its set-up (after the home was decided, after `tidy rotate`, after `launcher.log` was opened, after `<home>/norns`, `dust/`, `version.txt`, `matronrc.lua` and `sclang_conf.yaml` were looked at) and called `fail "norns is already running"` (a dialog from the desktop, a line in a terminal). There is no pid file or lock: the check is "a process named `norns` exists", on any home. A crash therefore leaves no lock to go stale.

**A finding while reading it:** because the check came late, a second start **rotated the running instance's logs** (`logs/norns.log` became `norns.1.log` under the running process), appended to `launcher.log` and could repoint `<home>/norns`. That touched the running instance's data. The check now comes first (right after the audio decision and before anything is written), and a test proves the home is byte for byte the same.

## What was built

1. **The launcher asks, the running matron raises.** The second launcher writes a request file `<norns home>/.norns-raise` and waits (4 s, `NORNS_RAISE_WAIT`) for the answer `<norns home>/.norns-raise.done`. Nothing else is written; no log is rotated, no setting touched.
2. **matron** (`sdl_bridge.cc`, inside `#ifdef NORNS_LINUX_DESKTOP`): a 300 ms SDL timer looks for the request (a `rename` to `.norns-raise.claimed` claims it, so one request is handled once), and the main thread then, for the screen window first (if the screen is detached) and the norns window last: restores it if minimised (`SDL_RestoreWindow`), shows it, `SDL_RaiseWindow` with `SDL_HINT_FORCE_RAISEWINDOW=1` (SDL then asks the window manager with `_NET_ACTIVE_WINDOW`, which is what switches to the window's desktop where the window manager allows it), and gives the norns window the keyboard focus. It answers `ok` (a window was asked to come forward) or `no-window`. At its own start it deletes any request or answer an earlier, crashed norns left.
3. **The launcher's reaction:** `ok`: exit 0 with the line "Verdandi is already running: its window was brought to the front", **no dialog**. `no-window`: the existing dialog with "Verdandi is already running but has no window to bring to the front." No answer in time (an old build, another norns home, a norns that is still starting, a norns running without a window): "Verdandi is already running, but it did not answer the request to show its window (it may be starting up, or using another norns home)." The home cannot be written: a sentence says so. **A second copy is never started in any of these cases.**

## Why this approach (compared)

| approach | needs | problems |
|---|---|---|
| **a control file, polled by matron (built)** | nothing: no package, no signal, no X11 library in the launcher | an answer within 0.3 s plus the launcher's poll; one more timer in matron; works the same on X11 and Wayland because the raise is done by the window's owner (SDL), not from outside |
| a signal (SIGUSR1) to the `norns` pid | a handler in matron | an older build, or a process that does not install the handler, is **killed** by the default action; no answer, no way to tell "handled" from "not" |
| `xdotool` or `wmctrl` from the launcher | the package | not installed by default (the task says not to require them); X11 only (they do nothing on Wayland); they would need the window's title or class; they cannot restore a window another way than the window manager lets them |
| `xdg-open`/D-Bus activation (a `.desktop` `DBusActivatable` service) | a D-Bus service file and a bus name in matron | a lot of new machinery for one raise; the .deb would have to install a service file |

## What works where

- **X11 with a window manager** (the owner's Cinnamon, XFCE, KDE, GNOME on X11): raise, restore from minimised and the keyboard focus are asked of the window manager through `_NET_ACTIVE_WINDOW`; whether it also switches to another workspace is the window manager's setting (Cinnamon and GNOME do, some tiling window managers do not). Not testable here: this container has no window manager.
- **X11 without a window manager** (the Xvfb tests): the stacking order and the keyboard focus change (XRaiseWindow, XSetInputFocus). That is what the test observes.
- **Wayland:** a client may not raise itself. SDL asks (xdg-activation where the compositor and the SDL build support it); the compositor may then only highlight the window in the panel (GNOME: "Verdandi is ready") or do nothing. matron answers `ok` when the request was made: it cannot know what the compositor decided, so no dialog is shown, and the window is not forced.
- **A minimised window:** restored on X11 by `SDL_RestoreWindow` (the window manager decides); on Wayland a compositor may ignore it.
- **A detached screen window:** both windows are raised, the norns window last (in front, with the focus).
- **norns running without any window** (no `screen:sdl`, or still starting): no answer or `no-window`, then the sentence above.

## Tests (written first)

- `linux/tests/second_start_test.sh` (no display, fake `norns` processes, a stub dialog): nothing running: the check lets a first start through (the hook `NORNS_CHECK_RUNNING_ONLY=1`), and a request file left by a crashed norns blocks nothing; a norns that does not answer: no second norns, the one sentence, the dialog, **the home snapshot (every path, size, time, content hash) unchanged**, the request file removed again; it answers `ok`: exit 0, "brought to the front", no dialog; it answers `no-window`: the sentence and the dialog; an old `.done` is not taken as the answer; `kill -9` of the running norns leaves no lock.
- `second_start_scenario` in `linux/tests/run_all.sh` (Xvfb, a real norns, `probe_second_start*.lua`, `second_start_check.sh`, `x_cover_window.py`, which plays "another window in front": a magenta window over the whole display with the keyboard focus): the second start exits 0, says "brought to the front", starts no second norns, shows no dialog, the box is in front of the other window afterwards (a pixel of the display), has the keyboard focus (another window had it before), leaves no control file; with the screen detached both windows are in front; norns is then killed with `kill -9` and a start on the same home with the old control files left boots normally, its matron clears them, and a second start still raises it.
- Existing launcher, probe and window tests are unchanged and pass (the first start is as before).
