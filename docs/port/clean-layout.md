# A clean norns home: inventory, layout and clean-up (plan only; nothing is built, nothing on the laptop is touched)

> **Status:** steps 1-3 built (launcher fix, `tidy flatten` dry run, `tidy` tool + CLEAN UP page + log limits); step 4 (build output: keep 2 .deb, status, clean, stage removed) built; the migration move (`--apply`/`--undo`) waits for the owner. See `STATUS.md`.

The owner's second design rule: **keep everything clean, easy to manage and easy to clean up; no build-up of files all over.** This is the inventory, the layout I propose, the SYSTEM page, the limits, the build output, and the migration of what already exists. **Nothing is moved or deleted until the owner confirms it in the chat** (questions at the end). Everything marked "measured" was run here in a scratch home; what I know about the owner's laptop comes only from the owner's reports (paths, `coredumpctl` list, the nested folder) and is marked "reported".

Pictures: `ui-previews/cleanup-page.png` (the proposed page, a stand-in drawn in the real window with example numbers), `ui-previews/cleanup-tree.png` (the folder tree). Made by `ui-previews/make_cleanup_pictures.py`.

## 1. Inventory

### 1.1 Why the home is nested (`~/Verdandi/Verdandi`): a bug, found and reproduced

- `linux/norns.sh` (installed mode) takes the home from `NORNS_HOME`, else the first line of `$XDG_CONFIG_HOME` or `$HOME/.config/verdandi/home`, else **`$HOME/Verdandi`**. Then (line 241) it does `export HOME="$NORNS_HOME"` so that everything it starts sees the norns home as `HOME`; **`NORNS_HOME` itself is not exported**.
- On a machine where PipeWire is the sound server (the owner's: Linux Mint, PipeWire) the launcher **runs itself again under `pw-jack`** (`exec "$PW_JACK" /bin/bash "$SELF" "$@"`, line 333, after the `export HOME`). The second run has `HOME=~/Verdandi`, finds no `NORNS_HOME`, and computes `$HOME/Verdandi` again: **`~/Verdandi/Verdandi`**. The second run is the real one: it creates a link `norns`, `dust/` and everything else *in the nested folder*, so the owner's scripts and data live in `~/Verdandi/Verdandi/dust` (reported: `.../Verdandi/Verdandi/dust/code/sidvagn`). The same happens when the home comes from `~/.config/verdandi/home` (the second run looks for the config under the new `HOME`).
- **Measured:** an installed-mode launcher with a fresh `HOME`, no `NORNS_HOME`, PipeWire stubbed so that the re-run is taken (the stubs of `launcher_test.sh`): the second run prints `DECIDE-HOME mode=installed home=<HOME>/Verdandi/Verdandi source=default link=create`; without PipeWire (our own jackd, no re-run) it prints `home=<HOME>/Verdandi`. The existing launcher tests all set `NORNS_HOME` explicitly, which is why nothing caught it.
- **What the outer `~/Verdandi` holds on such a machine** (measured in the scratch home; reported to be there on the laptop as a folder): from the first run, before it re-ran itself: a `norns` link, `dust/` with the empty `code`, `audio`, `data`, `matronrc.lua`, `version.txt`, `.config/SuperCollider/` (a copy of the sclang settings), `launcher.log`. **No user data** is expected in it, unless the owner used the app before PipeWire was the server or with `NORNS_HOME` set: the migration must look, not assume.
- **The fix is one line** (export `NORNS_HOME` before the re-run, and before `HOME` is changed; keep `NORNS_USER_HOME`), with a test that the installed default home survives the re-run (the missing test above). That is a code change, so it waits for the confirmation like the rest.

### 1.2 Everything Verdandi creates or leaves behind

"Pile up" = can grow without bound if nobody does anything. Sizes: measured in the scratch home after a headless boot, or read from the code.

| what | where | made by | needed | piles up | one-off |
|---|---|---|---|---|---|
| program tree | `/opt/verdandi`, `/usr/bin/verdandi`, desktop entry, icon, udev rule, `/usr/share/doc/verdandi` | the package | yes | no | no |
| the norns home | `~/Verdandi` (nested twice on PipeWire machines, 1.1) | launcher | yes | no | the nested copy is a bug |
| link `norns -> /opt/verdandi` | home | launcher | yes | no | no |
| `dust/` scripts, audio, data (`system.mods`, psets, `catalogs`), tape, **screenshots and GIFs** (`Verdandi <date>.png/.gif` in `dust/`), imported audio links (`dust/audio/mac`) | home | you, scripts, maiden, the window menu | yes: **yours** | **yes: captures and tape are yours and grow by use** | no |
| `audio.conf`, `audio.conf.failed`, `ui.conf` (and `ui.conf.tmp` for a moment) | home | SYSTEM > AUDIO and > UI, hand edits | yes (`.failed` is one-off: left when an audio start failed) | no | `.failed` |
| `matronrc.lua`, `version.txt` | home | launcher | yes, 2 tiny files | no | no |
| `norns.log`, `sclang.log`, `jackd.log`, `maiden.log` | home | launcher, **overwritten at every start** (`>`) | for diagnosis | **no, but the log of the run that crashed is lost at the next start** | no |
| `launcher.log` | home | launcher when started from the desktop (`exec >>`) | for diagnosis | **yes: append only, never cut** | no |
| `crash-report.txt` | home | the crash handler (`crash_report.cc`), **opened at every start (an empty file) and appended at a crash** | for diagnosis | **yes, slowly: appends forever** | the empty file at every start is noise |
| coredumps | `/var/lib/systemd/coredump` (reported: nine norns crashes in `coredumpctl list`) | systemd, not us | for diagnosis | system-managed (its own limits; **not verified** what they are on the laptop) | no |
| `.plugin-mismatch` | home | `plugin_arch_check` at every start | for the window note | **no** (rewritten); **always created, empty when nothing is wrong** | no |
| `.norns-restart`, `.norns-restart-audio`, `.norns-request-restart` | home | restart requests | transient | no (removed at start) | yes |
| `.mic-off`, `.norns-input` | home | the MIC button | yes, tiny | no | no |
| SuperCollider settings `.config/SuperCollider/sclang_conf.yaml` (`.old` when rewritten) | home (SuperCollider follows `HOME`) | launcher | yes | no | `.old` |
| SuperCollider extensions `.local/share/SuperCollider/Extensions` (a script's installer, mods, the **mi-UGens pack** the mod fetches, 3.5 MB; in future a **seeded** pack with a stamp) | home | scripts, mods, the launcher (planned) | yes, if you use them | **yes: each installer adds** | no |
| `disabled-plugins/` | home | **nobody**: the plug-in check only *prints* a `mv` command for you to run | no | only what you moved | yes |
| **`.cache/mesa_shader_cache`** | home | a graphics library, because `HOME` is the home | no | **yes: 1.5 MB after one boot (measured); the library's own limit is large** | yes |
| `~/.config/verdandi/home` | `~/.config/verdandi` | **you**, only to choose another home | only then | no | no |
| `/tmp` downloads of mods (e.g. the pack archive, removed by the mod) | `/tmp` | mods | no | no | yes |
| (developer checkout only) `build/`, `build/package/` | the repository | `linux/build.sh`, `linux/package.sh` | for building | see 5 | partly |
| tests (never on your machine) `probe.marks*`, `probe.fifo` | a test home | `norns_probe.sh` | no | no | yes |

**Needed:** program, home, link, `dust/`, the settings files, `matronrc.lua`, `version.txt`, SuperCollider settings and extensions. **Can pile up:** `launcher.log`, `crash-report.txt`, the Mesa cache, coredumps (system), captures and tape (yours), extensions (installers). **One-off leftovers:** the nested folder and what the first run left in the outer one, `audio.conf.failed`, `.old`, a `disabled-plugins` you made by hand, the temporary marks.

### 1.3 Build output of the repository (`build/`, 830 MB on this machine)

`build/package` is 789 MB: **`cache/` 704 MB** (`noble-build-base` 237 MB and `noble-minbase` 135 MB: the Ubuntu 24.04 bases of the clean-root build and test; `supercollider` 170 MB: the source clone; `sc3-plugins` 54 MB, `sc3-plugins-build` 34 MB, `sc-build` 33 MB, `maiden-home` 26 MB, `sc3-plugins-install` 17 MB, `libmonome`), `stage/` 59 MB (the tree of the package, rebuilt every time), `clean-root/` 13 MB (a second `.deb` of another version from the clean-root build), the newest `.deb` 14 MB, logs 0.5 MB. **Old `.deb` files do not pile up in `build/package`:** `package.sh deb` runs `rm -f "$OUT"/verdandi_*.deb` before it builds; the one in `clean-root/` is separate and is only replaced by the next clean-root build. What is wrong is that nothing says what the cache is, nothing clears it, and `stage/` stays.

## 2. One tidy layout

Everything Verdandi creates in the norns home lives in these places; nothing outside the home except the package files and the standard system places (`/opt/verdandi`, `/usr/bin/verdandi`, the desktop entry, the icon, the udev rule, `/usr/share/doc`; systemd's coredumps; `~/.config/verdandi/home` only if the user writes it).

```
~/Verdandi/                the norns home
  norns -> /opt/verdandi    link
  dust/                     YOURS (scripts, audio, data, captures): clean up never touches it
  audio.conf  ui.conf       YOURS (settings), stay where they are: two small files
  matronrc.lua  version.txt generated, tiny
  logs/                     the last 5 runs of norns, sclang, jackd, maiden (norns.log, norns.1.log ... norns.4.log); launcher.log capped
    crash/                  crash-2026-10-29-141502.txt ... the last 5, one file per crash, created only by a crash
  disabled/                 what Verdandi moved out of the way, with MANIFEST.tsv
  backups/                  made before any move of your files, with a manifest
  cache/                    libraries' caches (XDG_CACHE_HOME points here), capped, safe to delete
  .config/SuperCollider/    SuperCollider's own settings (follows HOME; cannot move)
  .local/share/SuperCollider/ extensions (follows HOME; cannot move)
  .norns-*  .mic-off  .plugin-mismatch   tiny marks
```
Four folders of ours, `logs/`, `disabled/`, `backups/`, `cache/` (and `logs/crash/`); the names say what they are. Why not more: `audio.conf` and `ui.conf` are read by the launcher, Lua, tests, the manual and by hand, and are **the user's files**: moving them buys nothing and risks the owner's existing ones (a `ui.conf` with the old `greys=` already converts). `matronrc.lua` is read by matron from `HOME`. SuperCollider's two hidden folders cannot move: it derives them from `HOME`.

**`disabled/` and its manifest.** One folder for everything Verdandi moves out of the way for the user (a wrong-architecture plug-in folder, an extension pack that collides, anything a future fix moves). Each item goes to `disabled/<id>/<original name>` with `<id>` = `YYYYMMDD-HHMMSS-N`; `disabled/MANIFEST.tsv` has one line per item: **id, what (the original name and kind), from (the full original path), when (UTC), why (a short reason: "32-bit ARM plug-ins on x86_64"), stored as, size, how to restore** (`verdandi tidy restore <id>`; the plain `mv` is also written so that it works without the tool). The file is written through a temporary file and renamed. **Restore** moves the item back to `from`, refuses if `from` exists, and marks the line restored. Nothing here is ever deleted by Verdandi except by the explicit clean-up below.

**One implementation**, a small shell tool `linux/tidy.sh` (installed as `/opt/verdandi/linux/tidy.sh`, reachable as `verdandi tidy ...`): `list`, `disable <path> <why>`, `restore <id>`, `remove-older <days>` (disabled/, logs, crash only), `rotate`, `usage`, `flatten` (the migration, 1.1, only with `--apply` and a typed confirmation). The plug-in check's message (`plugin_arch_check`, `plugin_check_test.sh`, `plugin_arch_test.cpp` expect the current text) changes from `mkdir -p '<home>/disabled-plugins' && mv ...` to `verdandi tidy disable '<folder>' 'wrong-architecture plug-ins (32-bit ARM)'`; the SYSTEM page's fix button (3) calls the same command, so a fix from the page and a fix from the message give the same folder and the same manifest line.

## 3. A SYSTEM page: CLEAN UP (my proposal; it is a separate page, below UI, because it is about files, not about looks)

See `ui-previews/cleanup-page.png`. Rows (E2 chooses, K3 opens or acts, K2 back; every number is read when the page opens, nothing runs in the background):
- **PROBLEMS** (only when there are any): one line each, e.g. `ARM PLUG-INS mi-UGens` with **K3 = MOVE TO disabled/** (asks once: "move 10 files, restorable? K3 yes, K2 no"). This is the fix action; it uses the same tool and manifest as the message.
- **DISABLED** n items, size: K3 lists the items (name, date, why, size); **K3 on an item = RESTORE** (once-confirm; says if the original place is taken).
- **LOGS** runs and size, **CRASHES** count and size, **SEEDED** packs (ours: they carry the stamp) and size, **CACHE** size: K3 shows the list; the only action inside them is the one below.
- **REMOVE > N DAYS** (E3 sets N: 30, 90, 180, 365): shows `5 items 9M` (what is older than N in disabled/, logs, crash reports, the cache, seeded packs) and **K3 asks once: "remove 5 items, 9 MB? K3 yes, K2 no"** and deletes exactly those.
- **Never touched, by design and by test:** `dust/` (scripts, samples, data, captures, tape), `audio.conf`, `ui.conf`, anything in `.local/share/SuperCollider/Extensions` that does not carry our stamp, anything outside the five groups, and anything in `disabled/` that the manifest does not list (a file the user put there by hand is shown as "not ours" and is not removed). Removing a seeded pack is allowed because it is ours and is re-seeded at the next start unless `seed=0` is set in `audio.conf`.

## 4. Limits, and what happens when nobody does anything for months

| growing thing | limit | after months of doing nothing |
|---|---|---|
| `norns.log`, `sclang.log`, `jackd.log`, `maiden.log` | at every start the previous log is kept as `.1`, `.2` ... up to **5 runs** (older ones removed); each file is also capped at **10 MB** while running (the launcher's one-second loop copies the last megabyte aside and truncates; the files are opened with append so that the writer stays valid) | at most 4 logs x 5 x 10 MB = **200 MB worst case**, a few MB in practice; and **the log of a crashed run survives the restart** (today it is overwritten: a real diagnostic gain) |
| `launcher.log` | **1 MB**, one `.1` | 2 MB |
| crash reports | one file per crash under `logs/crash/`, created **only at a crash** (no more empty file at every start), the last **5** kept | 5 small files |
| the Mesa cache | `cache/` via `XDG_CACHE_HOME`, `MESA_SHADER_CACHE_MAX_SIZE=64M` | at most 64 MB, safe to delete |
| `disabled/` | **never removed automatically**; it only grows with what the user moves, the page shows size and age | what the user moved, listed, restorable, removable from the page |
| seeded pack | one copy, replaced in place at a package update (stamp) | 3.5 MB |
| `.plugin-mismatch` | written only when something is wrong, removed otherwise | 0 or 1 tiny file |
| `backups/` | made only before a migration; listed on the page like disabled/; never removed automatically | what the migration made |
| captures, tape, scripts, samples, extensions that installers add | **yours: no limit, no automatic removal** | grows with use; shown nowhere as "clean up" |
| coredumps | systemd's own limits (**not verified** on the laptop: `coredumpctl list` shows them; Verdandi does not delete them) | system-managed |

## 5. Build output (`linux/package.sh`)

- **Keep the two newest `.deb` files** in `build/package` (one to roll back to) instead of one: change `rm -f "$OUT"/verdandi_*.deb` to remove all but the two newest; the clean-root build keeps one in `clean-root/` and says so.
- **`linux/package.sh status`** prints what is in `build/package` and what each cache folder is (the table in 1.3, with sizes) and which command clears it; **`linux/package.sh clean`** removes `stage/`, extra `.deb` files and the logs; **`linux/package.sh clean cache`** removes the cache (the next package build downloads and builds again, about the time of the first one: a number I will measure when it is built). `clean-root` already removes its root after a good build.
- **`stage/` is removed after a successful `deb`** (rebuilt every time; 59 MB).
- **The package never writes outside `/opt/verdandi`, `/usr/bin/verdandi`, the desktop entry, the icon, the udev rule and `/usr/share/doc/verdandi`** (the file list of the built `.deb` shows exactly that: 1540 entries, nothing else); `check_deb` already fails on a file outside those, and the plan adds a test that the **launcher** writes only into the norns home, `~/.config/verdandi/home` (read only) and `/tmp` (via mods): run it headless under a scratch `HOME`, list every new file outside the home and expect none.

## 6. Documents (short and plain; written with the build)

The Linux manual gets a new section "Files, and how to clean up": the tree of section 2 in five lines, what is yours, what Verdandi manages, the CLEAN UP page, the three commands (`verdandi tidy list`, `restore`, `remove-older`), what happens when you do nothing, how to move the home (`~/.config/verdandi/home`). `RUN-ON-LAPTOP.md` gets the same in a checklist: open CLEAN UP, check the numbers against `du -sh ~/Verdandi/*`, move a test plug-in folder to disabled/ and restore it, remove old items with the age row. The inventory table above goes into `docs/port/packaging.md`'s file list.

## 7. The migration of what exists (built only after the owner confirms; never automatic)

Goal: one home, `~/Verdandi`, with `logs/`, `disabled/`, `backups/`, `cache/` as above; the nested `~/Verdandi/Verdandi` flattened; the owner's scripts, data and samples never lost.

1. **First, the fix of 1.1** ships (so that a start after the flatten does not nest again). Then the owner runs `verdandi tidy flatten` without `--apply`: a **dry run** that only reads: what is in the outer home and in the nested home (names, sizes, counts), conflicts, absolute links that point into the nested folder (`dust/audio/mac` imports are links to the original files: those pointing elsewhere are fine), and the plan line by line. It changes nothing.
2. **`--apply` needs**: norns stopped (no `norns`, `sclang`, `jackd` of this home running), both folders on the same file system (so every move is a rename, no data is copied or deleted), and a **typed confirmation** (`flatten ~/Verdandi/Verdandi into ~/Verdandi`).
3. **Backup before anything**: `~/Verdandi/backups/flatten-<UTC>/` with `before.tree` (every path and size of both folders), a **hard-link copy** of the nested `dust/` (`cp -al`: instant, no extra space; protects against a wrong delete or rename; it does not protect against an in-place edit of a file during the move, which cannot happen with norns stopped) and, **if the owner prefers and the space is there, a full copy** (the dry run says how many GB), and the manifest.
4. **Outer leftovers** are not overwritten: an outer `dust/` that holds only empty folders is removed with `rmdir` (never `rm -r`); any outer file that is not byte-identical to its nested twin is moved to `backups/flatten-<UTC>/outer/`; outer `launcher.log`, `matronrc.lua`, `version.txt` are regenerated, not merged.
5. **Moves**: each top-level entry of the nested folder is renamed into the outer one with `mv -n` (no overwrite); on any conflict it stops with everything already moved listed in the manifest. The nested folder is removed only when empty (`rmdir`); otherwise it stays and is listed.
6. **Things that hold the old absolute path** are regenerated, not trusted: `.config/SuperCollider/sclang_conf.yaml` lists `<home>/dust` as an include path: the old file is kept as `.old` and a new one written (otherwise SuperCollider would stop compiling the scripts' classes: the one real risk of the move), the launcher's marks, `.plugin-mismatch`; links inside `dust` that point into the nested folder are reported and rewritten only on confirmation.
7. **Verify**: counts and total sizes of `dust/` before and after must match (the tool refuses to call it done otherwise), `before.tree` vs the new tree; a start of norns with the new home; the manifest lists every move as `from -> to` so that the reverse is the same moves backwards (`verdandi tidy flatten --undo <backup id>`).
8. **Logs and old crash reports** already in the home are moved into `logs/` and `logs/crash/` by the same tool (rename); the empty `crash-report.txt` is removed; `disabled-plugins/` becomes `disabled/` items with manifest lines reconstructed from what the plug-in check printed (the reason is then "moved by hand earlier").

## 8. Tests I would write first (each fails before)

`launcher_test.sh`: the installed default home survives the pw-jack re-run (and the `~/.config/verdandi/home` case); the launcher creates nothing outside the home (scratch `HOME`, new files listed); `tidy_test.sh`: `disable` + `restore` round trip and the manifest fields, restore refuses an existing target, `remove-older` removes only items older than N in the five groups and never touches `dust/`, `audio.conf`, `ui.conf`, an unstamped extension or an unlisted file in `disabled/`, log rotation keeps 5 runs and caps size, crash reports are created only at a crash and only 5 are kept, `flatten` dry run changes nothing, `--apply` on a fixture (nested `dust` with files, links, an outer leftover, a conflict, a stale `sclang_conf.yaml`) keeps every byte (sizes and checksums) and `--undo` restores the tree; the plug-in check's new message text (`plugin_check_test.sh`, `plugin_arch_test.cpp`); the SYSTEM page (`cleanup_page_test.lua`: numbers, confirmation required, K2 cancels, restore, nothing deleted without the confirm); `package.sh status`/`clean` on a fixture; the manual test (every `verdandi tidy` command named in the manual exists).

## 9. Risks

- **The flatten is the only step that touches user data**; hence the dry run, the typed confirmation, the same-filesystem rule (renames only), the hard-link backup, the manifest and `--undo`. A cross-filesystem home (a nested folder that is a mount) is refused.
- **`sclang_conf.yaml` with the old absolute path** (7.6) is the one thing that silently breaks scripts' classes after a move: covered above and tested on the fixture.
- **Rotating logs changes what a person finds**: `norns.log` stays the current one; `norns.1.log` is the previous run (documented).
- **Capping a running log** by truncation loses the middle of a runaway log, by design (the last megabyte is kept aside).
- **`XDG_CACHE_HOME` inside the home** moves libraries' caches there (a first start without a cache is a little slower); only `MESA_SHADER_CACHE_MAX_SIZE` and the location are set, nothing else.
- I did not see the owner's laptop: the nested folder's contents, the sizes of the owner's logs and cache, and the state of `disabled-plugins` are unknown until the dry run.

## 10. Questions for the owner (answer in the chat; nothing is built before)

1. The layout of section 2: `logs/` (with `crash/`), `disabled/`, `backups/`, `cache/`; `audio.conf` and `ui.conf` stay at the root. Names and places as shown?
2. The page: **CLEAN UP** below UI, with PROBLEMS (the fix action), DISABLED, LOGS, CRASHES, SEEDED, CACHE and REMOVE > N DAYS (30/90/180/365)? The only thing that deletes is the last row, after one confirmation.
3. Limits: 5 runs per log, 10 MB per log, `launcher.log` 1 MB, 5 crash reports, cache 64 MB. Other numbers?
4. Build output: keep 2 `.deb` (or 1), `package.sh status` and `clean [cache]`, remove `stage/` after a build?
5. The migration: flatten into `~/Verdandi` as described, with the **hard-link backup** by default (instant) or a **full copy** (needs the space)? And should the dry run be the first thing built, so that you can run it on the laptop and send me its output before anything is moved?
6. The one-line launcher fix (stop the nesting) can go in first, on its own, as a bugfix with its test: yes?
