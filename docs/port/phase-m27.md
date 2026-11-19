# Phase M27 (0.10.16): one Ext folders feature, the same on Windows and Linux; the old import items go from the Linux menu

Base: fc78536 (after M26, all green). macOS is not touched: every change below is inside `NORNS_LINUX_DESKTOP` (which the Windows build also defines) or in Lua pages that macOS does not have.

## What exists (read from the code)
- Windows: SYSTEM > EXT FOLDERS (`lua/core/menu/extra.lua`), the right-click item "Ext folders", the C rules in `platform/common/extfolders.c` (junction backend; a POSIX symlink backend is already in the same file and tested by `linux/tests/extfolders_test.c`). `_norns.ext_list/add/remove/pick/sync` are in `weaver.cc`, but inside the `NORNS_WINDOWS` block, so Linux never registers them. `extfolders.c` is not in the Linux build list (`norns/wscript`). The folder chooser (`sdl_bridge_pick_folder`) is Windows-only code, but it only calls `picker_open(PICK_FOLDER...)`, which is `platform/linux/file_picker.cc` (XDG portal over GDBus, then `zenity`, then `kdialog`) on both.
- Dropping on the window: a dropped path goes to the import queue; on Windows `dust_import_kind` is a stub that always says "skip", so every drop (file or folder) today only shows "importing is not available yet in this Windows build: copy the files into the dust folder". On Linux a drop is linked or copied into dust.
- Linux right-click menu: "Import files..." (Ctrl+O), "Import folder...", "Copy samples into dust", "Open the file dialog when a script loads a file". Old Import links are in `dust/audio/mac` (`DUST_LINK_DIR`); copies go straight into `dust/audio` or `dust/code`.

## What changes
1. `_norns.ext_*` are registered on Linux too (POSIX backend); `extfolders.c` joins the Linux build. SYSTEM > EXT FOLDERS appears on Linux from the same Lua page, and "Ext folders" is in the Linux right-click menu (it was Windows-only). The folder chooser is the existing Linux picker; when none is available the page says so in one plain sentence (nothing crashes).
2. Linux menu: "Import files...", "Import folder...", "Copy samples into dust" and the Ctrl+O shortcut are removed, with the code only they used (`menu_import`, `import_done`, `copy_samples`, `import_mode`, the Linux `SHELL_MENU_IMPORT*` / `COPY_SAMPLES` ids). "Open the file dialog when a script loads a file" stays, and the code behind it (`dust_import`, the `chosen` path, `shell_choose_file`) stays: macOS and that item use it.
3. Old imports are not lost: nothing is deleted. The page also lists the symlinks in `dust/audio/mac` (state ok / missing) marked "IMPORT" in place of the folder marks; removing one takes away only the link, after `lstat` says it is a link. Copies and real files in that folder are never listed or touched. The existing clean-up of dead links stays.
4. Drop on the window (Linux and Windows, same code): a folder is added as an ext folder (same rules and messages as the page), a file is refused with one short message and nothing is imported. macOS drop code is unchanged (`#ifndef NORNS_LINUX_DESKTOP`).
5. The page: a hint line at the bottom for the selected row ("K3 REMOVE  K2 BACK", on ADD FOLDER "K3 CHOOSE A FOLDER"); no new rows. The confirmation (K3 asks, K3 removes, K2 cancels) stays.

## What stays
The rules of `extfolders.c`, the junction backend, the confirmation, the file browser and tape page showing "[ext] <name>" (`ls -pL` follows the symlink; Windows has its own listing), the macOS import and its Finder link/copy, the "Open the file dialog" item.

## Tests (each is shown to fail on the old code in `phase-m27-without.txt`)
- C: `extfolders_test.c` extended with the legacy-link list/remove (a real file is refused, a copy is never listed, a path trick is refused); a new drop-classification test for the C helper.
- Lua: `extra_folders_page_test.lua` extended (hint line, legacy rows, drop handler); Linux build registers `_norns.ext_list`.
- Menu: `box_menu_test.sh` (no import items, "Ext folders" present, no Ctrl+O) and the window probes that clicked the removed items.
