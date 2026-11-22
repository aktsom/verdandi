# M33: Ext folders order, a hint on the ACTIONS list, DEVICE and CHANNEL apply with K3

Base: f9e1a0c (M32 pushed and green; no M31 exists). Version 0.10.20. Lua only (`lua/core/menu/extra.lua`, `lua/core/menu/midimap.lua`); no C, no macOS path.

## 1. SYSTEM > EXT FOLDERS: order

What exists: `rows()` in `extra.lua` lists the folders in the order `_norns.ext_list()` gives them, then ADD FOLDER, then (Linux) the old import links. After an add the selection goes to the new folder at its index in `m.items`.

What changes:
- ADD FOLDER is the first row, then the ext folders, then the old import links (Linux).
- Folders and links are each sorted by name with a pure function `m.natural_less(a, b)` (exported for the test): case ignored; the name is cut into digit runs and other runs; a digit run is compared as a number (2 before 10; equal numbers: the shorter run, so `02` after `2`); a digit run comes before a letter run (a name that starts with a digit comes before a name that starts with a letter); other runs are compared as lower case text; a tie falls back to the exact text so the order is the same every time. BLOCKED, MISSING and NO LINK folders are sorted by name with the others (the mark is not part of the key).
- After an ADD (picked or dropped) the selection goes to the new folder at its place in the sorted list (not to ADD FOLDER: you see what you added). If it is already in the list (added twice) the selection goes to that one.
- After a REMOVAL the selection stays on the same row number, so it lands on the next folder (the row that moved up); if the removed row was the last, on the new last row; with nothing left on ADD FOLDER. It never leaves the page.
- The page opens with the selection on ADD FOLDER (row 1). The hint lines (`K3 REMOVE  K2 BACK`, `K3 ADD A FOLDER  K2 BACK`) are unchanged.

## 2. MIDI MAP > ACTIONS: a hint that E3 right opens the action's page

What exists: the line under the list says `K3 LEARN  E3 < CLEAR  VIEW >` for an action with nothing set, `PIN = NOTE 36` (and the channel) for a set one, `ALSO X` when two actions share a message. The owner did not find the page behind E3 right (its DEVICE and CHANNEL rows).

What changes: while no learn is on, the right end of the title line says `E3 > MORE` (dim, the same place as `MIDI MAP` on WATCH). It is there for every action row, set or not, so it does not depend on which message the bottom line shows. The bottom line for an action with nothing set becomes `K3 LEARN  E3 > MORE  < CLEAR` (the same length as before, the cryptic `VIEW >` gone). Nothing else changes; K3 = learn exactly as before; ASSIGN ALL and CLEAR ALL rows show no `E3 > MORE` (E3 does nothing there).

## 3. DEVICE and CHANNEL apply with K3

What exists: E3 on a DEVICE or CHANNEL row sets the value at once (saved at once); K3 on DEVICE steps to the next device. Scrolling past a device that is not the Push makes the controller stop working for a moment.

Rows concerned (all of them): the two top rows (M32), the DEVICE and CHANNEL rows of a control's view (E1-E3, K1-K3, A1-A4) and of an action's view.

What changes:
- E3 only moves a *waiting choice* (`m.wait = {scope, field, value}`): the row shows the choice in square brackets, `[MIO]`, `[3]`, `[GLOBAL]`; the bottom line says `K3 APPLY  K2 DROP` while a choice is waiting. Nothing is applied or saved. The value the messages use (`S.eff_dev`, `S.eff_ch`, `midimap.conf`) does not change.
- K3 applies the waiting choice (through the same setters as before, saved at once) and clears it. With nothing waiting K3 on these rows does nothing (it no longer steps).
- K2 drops the waiting choice and stays where it is (a second K2 goes back as before). Moving to another row with E2, leaving the view, leaving the page, a learn and a preset change also drop it.
- A choice equal to the value in use is not "waiting" (the bracket goes away): there is nothing to apply.
- All K3 sources (the mapped controller, the keyboard, the on-screen K3) already end in `page.key(3, 1)`: the same handler, so they behave the same.
- Other rows (NUMBER, TYPE, MODE, SENS, ...) and LEARN (what it stores for device and channel) are not changed.

## Tests (each shown to fail on the old code in `docs/port/phase-m33-without.txt`)

- `linux/tests/extra_folders_page_test.lua`: the order function (digits, letters, mixed case, 2 and 10, 02, names with marks), the page with several folders (ADD FOLDER first, sorted, a blocked and a missing one, old import links after the folders, sorted), the selection after an add and after removals, the hint lines.
- `linux/tests/midimap_page_test.lua`: the ACTIONS list text, K3 still starts a learn; E3 scrolls without applying for the top rows, a control, an arc encoder and an action; K3 applies; K2, E2 and leaving drop; K3 with nothing waiting changes nothing; `midimap.conf` changes only on K3.
