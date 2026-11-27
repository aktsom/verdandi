# M38: ext folders are sorted by their real name (Linux and Windows, shared Lua)

## Where the sort happens
An ext folder is a link `[ext] <name>` in `dust/audio` (`platform/common/extfolders.h`). Every file browser lists a folder through `util.scandir` (`lua/lib/util.lua`): `fileselect.lua:123` (the script browsers, the tape page, anything that calls `fileselect.enter`) and the params file picker (`params/file.lua:81`). The sorting is done by the platform, on the TEXT of the entry:
- Linux: `ls -pL --group-directories-first`, in the locale of the user (case, accents and punctuation as the locale says; digits are not read as numbers: `10` before `2`).
- Windows: `_norns.listdir` (`weaver.cc`), folders first, then `std::sort` on the bytes of the names (uppercase before lowercase).
So `[ext] bass` sorted as `[ext] bass`: with a locale that ignores punctuation it landed in the `e` names, with bytes after the capitals and before `a`. The tape page lists only recordings (`menu/tape.lua`, `ls _path.tape`); it has no ext folders. The SYSTEM > EXT FOLDERS page has its own order (`menu/extra.lua`, `natural_less`, ADD FOLDER first, then A-Z) and is not touched.

## What changed
`util.scandir` hands its listing to `util.ext_place` (new, `lua/lib/util.lua`). Without an `[ext] <name>/` folder entry the listing is returned as it is (so macOS, which has none, and every other folder are unchanged). With ext folders:
- the normal entries are not moved and not re-sorted: they keep the order the platform gave them (the rules the user knows);
- each ext folder goes inside the folder group to the place a normal folder called `<name>` would have, by the order of the platform: Windows compares the bytes (the same as the native listing); Linux asks the program `sort` with the same environment as `ls` (one call, a temporary file with the names; if that cannot be done: lower case text, then bytes);
- the shown text and the names are not changed (`[ext] bass/` stays), so selecting, the stored links and what they point at are as before;
- the same name as a normal folder: the normal folder first, then the ext entry (the real folder is there first, and the order is the same at every listing); two ext entries with one name keep the order of the listing.
Files stay after the folders, in the platform's order.

## Tests
`linux/tests/ext_sort_test.lua` (in `run_all.sh`, Lua shard): ext folder `bass` among `a`, `b2`, `c`, `e1`, `e2`, `zed` on the Windows and the Linux path, digits (`05` before `10`, `15` between `10` and `1x`), mixed case (byte order and a case-folding `sort`), same-name collisions, "[ext] " files and look-alike names are not ext folders, no ext folder = unchanged, the EXT FOLDERS page and `fileselect` still use their own code. 9 checks fail on the old `util.lua` (`phase-m38-without.txt`).

## Not tested here
A real `ls` in the owner's locale (here only the C locale exists), the real Windows listing, the real browser on screen. `docs/port/HARDWARE-CHECKLIST.md`.
