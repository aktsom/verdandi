# Proposal (not built): showing the full name of a long item in the file selection browser

Status: **proposal only. Nothing in this document is implemented**, and nothing about how `fileselect` or a script's `screen.text` draws has been changed. It needs the owner's decision.

## The behaviour today (upstream, kept)

`lua/lib/fileselect.lua` (`fs.redraw`) draws every row as `screen.text(name)` at x = 0 and the length of an audio file as `screen.text_right(length)` at x = 128 on the same baseline. A name wider than the free room runs under the length and off the right edge of the 128 x 64 surface. The owner confirmed that the Raspberry Pi hardware does the same, so this is upstream behaviour, not a port bug. Only a row that is being previewed is cut (`util.trim_string_to_width('* ' .. text, 97)`). Measured with the real font (`linux/tests/page_width_test.lua`, `font_widths_dump.c`): the menu font is about 4 to 5 pixels per character, so a name longer than about 28 characters is cut by the edge, and about 20 characters when a length is shown at the right.

Our backend draws the same pixels as plain cairo on the same surface (`linux/tests/screen_text_test.cc`, "a text wider than the screen is clipped at the screen edge"); the real window shows the same clipped single line. So there is nothing to fix in the backend, and the options below are additions, not corrections.

## Options (desktop only: `NORNS_LINUX_DESKTOP` in C, `NORNS_PLATFORM` in Lua; all off by default)

1. **A toast / status line with the full name (recommended first step).** After the selection has rested for about 0.4 s on an item whose name is wider than the room, the Verdandi window shows the whole name in the existing toast pill under the buttons (`matron/src/platform/linux/screen_toast.c`, three lines at most, long words cut), and hides it when the selection moves or the browser closes. It is drawn by the window around the norns screen, **not** on the 128 x 64 surface: the pixels a script and the browser draw are exactly what they are now, on screen and in screenshots and GIFs of the screen. Hook: a call from `fs.redraw` (or from `fs.enc`) into `_norns.toast(...)` only when `NORNS_PLATFORM` is set. Cost: small (about 30 lines of Lua, one setting `file_names_toast`, the existing toast fit tests). Limit: with the screen detached into its own window the pill is on the main window; the text must be sent to whichever window shows the screen (the toast code already handles both).
2. **One-line marquee for the selected row.** The selected (level 15) row scrolls its name sideways by one pixel every 60 ms after a pause, bounded by the room, and snaps back when the selection changes. This changes pixels that the browser itself draws, so it is the option that departs from upstream. Needs a timer: not a Lua metro (31 to 36 are reserved by the menu and 1 to 30 belong to scripts), better a tick from the window's own loop calling a redraw of the browser only while it is open. Effect on frame rate: one redraw per tick while a long name is selected. Setting `file_names_marquee` (off by default) so that anyone who wants the device's look keeps it.
3. **A detail key.** K1 held (or E1) shows the name in two or three wrapped lines over the list until released. It uses an input the browser does not use today, but scripts can bind K1/E1 around the browser in their own handlers (rerouted while the browser is up), so a script that expects the keys unchanged is the risk. Not recommended.
4. **A mouse tooltip over the screen part of the window** with the full name of the selected row. Costs a hit test and the window text path; the least intrusive for scripts (they never see it) but only for mouse users.

## Effect on script compatibility

- `fs.enter`, `fs.exit`, `fs.pushd`, the callback with the chosen path (or `"cancel"`), the rerouting of `redraw`, `enc`, `key` and `refresh` through `norns.menu.set`, and the list contents stay as they are in every option. Option 1 and 4 add no drawing to the surface and no key or encoder use: a script cannot tell the difference. Option 2 changes what the browser draws on its own page (a script cannot depend on that, but a screenshot or a video of the browser differs). Option 3 changes input use.
- All options are guarded to the Linux desktop build; the Raspberry Pi and macOS builds are untouched.
- Tests that would come with the first step (tests first): the toast text is the full name and fits the three-line fit rules; it appears only for a name wider than the room; it goes when the selection moves or the browser exits; the surface (the exported PNG of the screen) is byte-identical with the toast on and off.

## Decision needed

Whether to build option 1, which of 2 to 4 to add (if any), and whether it should be a setting that is on or off by default.
