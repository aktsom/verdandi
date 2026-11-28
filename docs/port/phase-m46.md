# M46 (Linux desktop): the right mouse button on a virtual grid key (kept, documented, protected by a test)

## The owner's question
A right click on a virtual grid key works like the Shift latch (the key stays down after the button is released). Is it deliberate, what exactly does it do, is it documented?

## Answer (read from `matron/src/platform/macos/sdl_bridge.cc`, the grid window's mouse handler)
- **Deliberate, and not from M41 or M43.** It is in the original grid window code of the Mac app: the header comment of the file says "click a key to press it, drag across keys to play them in turn, right-click (or ctrl-click) to latch a key down, for chords". M41 left the handler alone. M43 changed only Ctrl: on the Linux desktop Ctrl + the left button now stages a chord (`#ifdef VGRID_ROTATE`), and the code comment there says "the right button is the latch"; on the Mac build Ctrl-click still latches.
- **What it does (a toggle, on the press, the release is ignored):** right button down on a key that is not latched: the key-down goes to the script (`grid_press`) and the key gets the latch flag, so it stays down when the button is let go. Right button down on a latched key: the flag is cleared and one key-up is sent (only when nothing else holds the key: not the mouse, not a fired chord).
- **A left click on a latched key** presses it again and lets it go when the button is released (the latch flag is replaced by the mouse's): the script gets a key-down and a key-up.
- **Shift latch (M41):** the keys that Shift holds after its release use the same latch flag. A right click on one of them lets it go once (one key-up); the plain left click that would end the Shift hold afterwards sends no second key-up for it.
- **Ctrl chord (M43):** the right button is not part of it: with Ctrl held a right click latches as usual (the chord staging is the left button's), and a latched key is not changed by Ctrl up (nothing staged, nothing fired).
- **Plain click, drag, size and ROT buttons:** unchanged.
- **Documented before M46:** only in that source comment and as "right click unchanged" in the M41 and M43 notes; the manual said "the right mouse button holds a key down until you click it again" in one sentence; the window did not say it.

## What changed
No behaviour change. The one-line hint under the keys now reads "Shift = hold    Ctrl = chord    Right click = latch" (`VGRID_HINT` in `vgrid_skin.h`, Linux desktop only; it fits under the smallest grid: tested). The manual says it in the virtual grid paragraph. The branch is now a Linux desktop condition of its own (`b->button == SDL_BUTTON_RIGHT`), so it is no accident of how the buttons are read: a test fails when it stops latching.

## Tests (`docs/port/phase-m46-without.txt`)
- Headless, the real window on Xvfb (`probe_vgrid_rclick.lua`, test "window:virtual grid right click latches a key ..."): one right click = one key-down that stays; the second = one key-up; two keys latched and a plain left click elsewhere leaves them; a left click on a latched key lets it go; a right click on a Shift-latched key lets it go once and the next plain left click sends no second key-up; the right button with Ctrl held latches, the next right click lets go. Fails when the right button stops latching (proof file).
- `vgrid_skin_rot_test.c`: the hint names Shift, Ctrl and the right click and fits under the 64-key plate (Linux build); the Mac build's picture is unchanged (golden hashes).
- `vgrid_pane_check.sh` has a new `rclick` command (xdotool, button 3).
