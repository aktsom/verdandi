# M32: one DEVICE and CHANNEL for all mappings in MIDI MAP, and the full device name in WATCH

Base: 31c3a0d (M30 green). Version 0.10.19. Lua only (`lua/core/midimap_settings.lua`, `midimap_value.lua`, `midimap.lua`, `menu/midimap.lua`); no C, no macOS path.

## What exists today (read in the code, not assumed)

- Every mapping is matched in one place, `matches(c, d, ch)` in `core/midimap.lua` (a control: E1-E3, K1-K3, A1-A4; an action too), plus the same device test in `clashes()` and the overlap test `find_overlap()`.
  - `c.ch == 0` means any channel, `c.dev == "ANY"` means any device that is a controller (`V.is_non_controller` leaves out the keys window and monome iii), otherwise `V.name_matches` (the name, its numbered ports, or `=Name` for exactly one port).
- A control has DEVICE and CHANNEL rows in its view. **The actions have them too**, in their own view (ACTIONS list, E3 right on an action opens it: LEARN, KIND, NUMBER, DEVICE, CHANNEL ...). The request says the actions have none; that is not so in 0.10.18, so the report says it plainly. Nothing is removed and the ACTIONS list is not changed. The action views use the same choices as the control views, so they get the same first choice described below.
- LEARN stores the port the message came from (`port_of`, the name norns gives the port, `=Name` when another listed name would also match; "ANY" only for a device without a name) and sets the channel to 0. The preset files and the built-in presets name no device and no channel; applying one sets every mapping to ANY and 0.
- WATCH shows `fit(dev:upper(), 56)` at the left, `CH n` at x=62 and `CC n` at x=96 on one line, so a long name is cut ("ABLETON PUS..").

## What changes

1. **Two settings for everything**: `S.state.global = {dev = "ANY", ch = 0}`, written to the owner's `midimap.conf` as `global.dev=` and `global.ch=` (not in preset files, not touched by selecting, saving or deleting a preset, not a reason for the label CUSTOM). A file without these lines reads as ANY and any channel, so an old file behaves as before.
2. **How a mapping says "follow the global setting" and "any device even though a global one is set"** (the simplest for the owner):
   - the first choice of a mapping's DEVICE row (and CHANNEL row) is **GLOBAL**: it follows the top row. It is the default. It is stored as the value that has always meant "no device chosen" (`dev=ANY`, `ch=0`), so every old file and every old preset keeps its meaning: with the top rows at ANY, GLOBAL is exactly "any device, any channel" as before.
   - the second choice is **ANY**: any device (any channel) even when the top row names one. It is stored as `*` (device) and `*` (channel, kept as 17 inside), a new value that old files do not have.
   - then the devices by name, and 1 to 16, as today. A device or channel of its own always wins over the top row, for that mapping only.
   - the top rows themselves have ANY (the default) and the names / 1 to 16.
3. **Actions follow the top rows** like every other mapping (they have no extra place in the ACTIONS list; the list looks as today). Their own view keeps its DEVICE and CHANNEL rows, with GLOBAL as first choice.
4. **LEARN** keeps its rule: the device it stores is the port the message came from (when the device has a name), the channel goes back to the default. "Default" is now GLOBAL: after a learn the channel follows the top row. A device stored by LEARN is the mapping's own device, so it wins over the top row (that is how it works today with ANY). The built-in presets and saved presets still carry no device and no channel.
5. **WATCH**: the device name gets a line of its own and is shown in full, the same text as the DEVICE rows (`name:upper()`; the name norns gives the port, "ABLETON PUSH 2 2"). `CH n` and `CC n` move to the line of `LAST SIX`, right-aligned. A name that is wider than the screen keeps its end (".." and the last characters) so that the port number stays visible. Nothing else on the page changes.
6. **Page**: two rows at the top of the main list, DEVICE and CHANNEL (E3 turns, K3 cycles, as in a view). The page still opens with the selection on PRESET (now row 3).

## What stays

macOS and every C file; the built-in presets; the preset file format; the ACTIONS list; the other rows; the matching rules (`V.name_matches`, `=Name`, the non-controller devices) - only *which* device and channel value is looked at changes, and only when a top row is set.

## Tests (each shown to fail on the old code in `docs/port/phase-m32-without.txt`)

- `linux/tests/midimap_global_test.lua`: all kinds of mapping (control, arc encoder, action) ignore another device or channel when a top row is set and accept the right one; own device or channel wins; GLOBAL and ANY; old conf with and without dev/ch lines unchanged at default; conf round trip; presets leave the global alone and carry no device; overlap and clash use the effective values.
- `linux/tests/midimap_page_test.lua` (existing, row numbers moved by two) plus new checks for the two rows and the WATCH text with the owner's two Push names, a 40 character name and a name with a port number.
