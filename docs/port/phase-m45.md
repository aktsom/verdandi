# M45 (Linux desktop only): the virtual grid never moves a real grid's slot

## What the owner saw
Laptop, package 0.10.22-3649 (M42 + M43). The real grid is set to grid slot 2, slot 1 is "none"; a mod (sidvagn) takes over the grid that is set in slot 2 and cannot work if the real grid leaves slot 2. Turning the virtual grid on put it in slot 1 (fine). Turning it off put the REAL grid in slot 1 and set slot 2 to "none": the mod lost its grid. Also, while the virtual grid was on, the real grid's LEDs stayed on the last picture.

## Where the real grid was moved (read from M43's code, `lua/core/grid.lua`)
It is M43's "hand control back" logic, not matron's slot assignment. matron's `Grid.new` only fills the first "none" slot with a grid it has not seen; `Grid.update_devices` only maps names in slots to devices. The move was in `give_back()`:
- With the real grid in slot 2 and slot 1 "none", `Grid.new` puts the virtual grid in slot 1 (the first free slot) and `take_over()` returned at once (`prev == g.name`): no `Grid.switch` was recorded, because no grid had been pushed out of slot 1.
- When the virtual grid went, `give_back()` found no remembered grid (`want = nil`), fell back to "any other grid", took the real grid, wrote its name into slot 1 and then `Grid.vports[slot].name = "none"` for the slot it had been in (slot 2). That is the owner's report, exactly.
- The same fallback would also have moved a real grid from slot 3 or 4, and would have overwritten a slot that the owner changed in SYSTEM > DEVICES > GRID while the virtual grid was on.
- The saved settings (`core/state.lua`) wrote the slot names as they were at that moment, so a restart with the virtual grid on saved the virtual grid's name as slot 1.

## The rule now (one implementation, `lua/core/grid.lua`, Linux desktop only; nothing special for any mod)
The virtual grid never moves a real grid's slot for good. What the switch changes is written down with the value before it (`Grid.switch.ov[slot] = {set, pre}`), and at the end only these slots are put back, and only those that still hold what the switch wrote.
1. **On:** the virtual grid takes slot 1. A real grid in any other slot stays exactly where it is (slot 2 with slot 1 "none": nothing else changes).
2. **Off:** the slot the virtual grid used goes back to what it was (slot 1: "none"). The real grid stays in its slot.
3. **Real grid in slot 1 when it is turned on:** the virtual grid still takes slot 1 (scripts use it at once); the real grid goes to the first free slot (2, 3 or 4) and goes back to slot 1 when the virtual grid goes; the slot it was parked in goes back to "none". If all slots are taken the real grid has no port while the virtual grid is on and is in slot 1 again afterwards.
4. **Unplug and plug in again while the virtual grid is on:** a plugged-in grid whose name is in a slot goes to that slot (matron's own rule), so it returns to the slot it has, not to a new one; the slot it has is either its own or the one it was parked in, and the end of the switch puts slot 1 right.
5. **What the owner sets meanwhile stays:** a slot that does not hold what the switch wrote any more (changed in the menu) is not touched.
6. **Saved settings:** `Grid.persistent_name(i)` gives `core/state.lua` the value from before the switch for the slots the switch holds, so a restart with the virtual grid on neither saves the virtual grid's name nor moves a real grid; an older settings file that has the virtual grid's name in a slot is cleaned when the virtual grid is added (that slot is "none").
7. No real grid at all: slot 1 "none" -> virtual grid -> "none". A real grid that is not plugged in but has its slot setting (the name stays in the slot) is slot 1 again afterwards (before M45: "none").

## The LEDs (the question of the frozen picture)
- Before M45: C copied the LEDs between the virtual grid and "the first other grid" in the device list, whatever its slot (`dev_list_grid_other`). Turning the virtual grid on copied the real grid's picture to the virtual grid; turning it off copied the virtual grid's picture over the real grid, which was in slot 2 and driven by someone else.
- Now Lua tells C which real grid takes part (`_norns.grid_peer`, `core/grid.lua publish_peer`): the real grid in slot 1, or, while the virtual grid is on, the one it pushed out of slot 1; none when slot 1 has no real grid. Only that one is copied from and to. A real grid in another slot is never written to by the switch.
- So with the real grid in slot 2 its picture stays as it was while the virtual grid is on, and it is changed only by whatever draws on slot 2 (the mod, a script on port 2). If nothing draws, it stays frozen on the last picture: that is expected, Verdandi does not touch it. With the real grid pushed out of slot 1 (case 3) it goes dark when no script listens on its new port (M43), and gets the virtual grid's picture back when it takes slot 1.

## Tests (fail on the M43 code: `docs/port/phase-m45-without.txt`)
- `linux/tests/grid_slots_test.lua` (Linux; the Mac variant is skipped): real grid in slot 2 with slot 1 none, five on/off (slots, port, saved settings, peer); real grid in slot 1 (five); unplug/replug while on (from slot 2, from slot 1, plugged in while on); no real grid (five); real grid in slot 3; two real grids; all slots taken; a slot the owner changed meanwhile; the saved settings while on, an old file with the virtual grid's name; no error in the log.
- `linux/tests/grid_switch_test.lua` (M43): one expectation changed: a real grid that is not plugged in keeps its setting for slot 1 afterwards.
- Headless, the real program on Xvfb (`probe_grid_slot2.lua`): a test real grid in slot 2, five times window open and closed: slots, the real grid's port and its LED picture unchanged each time.

## Not changed
macOS (the Lua switch is behind `NORNS_PLATFORM == "linux"`, the C peer is Linux desktop only), Windows (no virtual grid), the mod's way of taking the grid set in slot 2, key release for a held key on a grid that is left (M43), the size announcement (`Grid.add` for the grid that takes over).
