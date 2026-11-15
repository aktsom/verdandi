# Phase M15 (Windows 0.10.6): cheat codes 2 did not load

The owner's report (build 0.10.5): loading cheat_codes_2 gives "SCRIPT ERROR: load fail" and "MISSING INCLUDE: lib/cc_pattern_time" at cheat_codes_2.lua:84, with the nested "script load ... lib/fail_state-nb.lua" before it. Installing the library nb did not change it.

## 1. What cheat codes 2 checks (read from the source)
Source: https://github.com/dndrks/cheat_codes_2 (the community catalog entry says `dndrks`, not `dstaas`), commit 7134bd5 (rev 250929 LTS13.3). The first lines of `cheat_codes_2.lua`:

```lua
if tonumber(norns.version.update) < 250406 then ... fail_state-update.lua end
if not util.file_exists(_path.code..'cheat_codes_2/lib/nb/lib/') then
  norns.script.clear()
  norns.script.load('code/cheat_codes_2/lib/fail_state-nb.lua')
end
```
So it tests whether **a folder exists: `cheat_codes_2/lib/nb/lib/`, inside the script's own folder**. That folder is the script's own copy of nb, a **git submodule** (`lib/nb` -> github.com/sixolet/nb, `.gitmodules`). It is not `dust/code/nb` (which is why installing nb changed nothing), not a mod, a global, an nb player, or a Lua version. The nested script `fail_state-nb.lua` only draws "delete cc2 via maiden and re-install a fresh copy". Later the script does `include 'lib/nb/lib/nb'`.

## 2. The cause on Windows
`util.file_exists(name)` is `io.open(name, "r")`. On a norns (Linux) `fopen` of a **folder** succeeds (it fails only when reading), so the function is true for a folder and scripts use it that way (cheat codes 2; `util.file_exists(_path.code.."nb")` and `.."passthrough"`, `.."midigrid"`, `.."namesizer"`, `.."mx.samples"` are common). On Windows `fopen` of a folder **fails** (access denied), so every "does this folder exist" through `util.file_exists` was false there, whatever was on disk. Nothing the script needs is missing from Windows; the shared function behaved differently.

Same cause, other effects on Windows until now: `script.lua` tested the script's data folder and its `data` folder with it (the data folder was "initialised" at every load, and the script's default psets were never copied because `<script>/data` was never found), and the integrations that look for passthrough, midigrid, namesizer, mx.samples were always off.

**Fix (Verdandi, not the script):** a native `_norns.path_is_dir(path)` (GetFileAttributesW, UTF-8, trailing slash fine; `norns_win_is_dir` in `posix_compat.c`) and `util.file_exists` asks it when `io.open` fails. On Linux and Mac nothing changes (the native function does not exist there).

**What the first Windows CI run showed (commit 2852989):** the reproduction worked in the real program: with the old `util.file_exists` cheat codes 2 loaded `fail_state-nb.lua` inside its load and then stopped with `MISSING INCLUDE: lib/cc_pattern_time` and `load fail` at `cheat_codes_2.lua:84`, line for line the owner's log. maiden installed the script from the real catalog with its submodule (5 files in `lib/nb`) and nb by address, and wrote the install, the submodule and the removal to maiden.log. The fix itself still answered false: scripts see `/home/we/dust/...` and `lua/core/virtual_home.lua` translates a path only for the `_norns` functions on its list; `path_is_dir` was not on it, so the native check looked at `/home/we/...`, which does not exist on Windows. It is on the list now, with a test (`file_exists_virtual_home_test.lua`) that fails without it.

## 3. Why the include fails after the nested load: the same on a hardware norns
`norns.script.load` runs the new script with `dofile` **inside** the running one, sets `norns.state.path` to the new script's folder (`.../cheat_codes_2/lib/`) and returns; cheat codes 2 does not stop after it. `include 'lib/cc_pattern_time'` (lua/core/startup.lua, as upstream) searches `norns.state.path`, then `_path.code`, then `_path.extn`: `.../lib/lib/cc_pattern_time.lua` is not there, so MISSING INCLUDE at line 84, the first include after the check. This is **not** Windows-only: a hardware norns would do exactly the same if the check failed. It is only the second symptom; the first was the failed check. (Reproduced on Linux by making the check answer false for a name that ends in "/": the log is the owner's, line for line: load, nested fail_state load, MISSING INCLUDE, "load fail", cheat_codes_2.lua:84.)

## 4. maiden's project manager
- maiden (pinned commit 2e64f7d) has **no dependency handling**: no field in the catalog entry (the 354 entries of community.json have `project_name, project_url, author, description, discussion_url, documentation_url, tags`, no dependencies), no code. cheat codes 2 needs none: nb is its own submodule.
- Installing from the catalog does `git clone` with **submodules** (go-git `RecurseSubmodules`): run here with the same code, `lib/nb/lib/nb.lua` and `player.lua` came with it. A **zip** install (a GitHub "download zip") has no submodules: `lib/nb/` would be empty, which is the case the script's "delete cc2 via maiden and re-install a fresh copy" is about. Re-install over an existing folder is refused by maiden ("already exists"), so the folder has to be removed first.
- **Logging:** maiden logged only the catalog fetches and (gin) one line per request, with no name, no error text and nothing on submodules. New patch `linux/patches/maiden-install-log.patch` (applies to the Windows and Linux builds): `install: <name> from <url> into <path>`, `install: <name> done in .. ms; submodule lib/nb: 5 files` (or `is EMPTY`), `install: <name> FAILED after ..: <error>`, `remove: <name> removed`. They go to `logs/maiden.log`.

## 5. Tests
- Lua `linux/tests/file_exists_dir_test.lua` (in `run_all.sh`): io.open refuses folders (Windows), a stand-in for the native check; folder with and without a slash, file, missing name, file with a slash, and the old function failing for the existing `lib/nb/lib/` (the owner's failure).
- Real program on Windows (CI, `windows/ci/maiden_probe.py` VERDANDI_PROBE=cc2, `smoke-m1.sh` m15-run-cc2-probe / m15-check-cc2): maiden installs cheat_codes_2 from the real catalog and nb by address; the submodule is on disk; `util.file_exists` on a folder with a slash, a folder, a file, a missing folder; cheat codes 2 loaded with the old `util.file_exists` (io.open only) reproduces the owner's log; loaded with the real one it includes `lib/nb/lib/nb.lua` and stays loaded; maiden.log has the install, submodule and removal lines. No network: the check says SKIP.
