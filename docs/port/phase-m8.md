# Phase M8: extra sample folders (Windows 0.9.0)

Approved design: `docs/port/extra-folders-proposal.md`, option B. A folder the owner adds is made visible as a link `dust/audio/[ext] <name>`, so the norns browser, the tape page and scripts see it as an ordinary folder. Nothing in fileselect, the tape page or virtual /home/we changes.

## Approach (written before the code)

1. **One small C core, `matron/src/platform/common/extfolders.{h,c}`**, with the rules in one place and two thin backends:
   - POSIX (symlink; used by the Linux tests, so the rules are tested on Linux CI as well),
   - Windows (junction through `FSCTL_SET_REPARSE_POINT`, wide API, `\\?\` for long paths).
   Functions: `ef_add`, `ef_remove`, `ef_sync`, `ef_list`, `ef_scan_audio`. Paths are UTF-8 everywhere.
2. **Rules on add** (each refusal is one plain sentence): not a folder / not there; a network path (UNC, or a mapped drive: `GetDriveTypeW == DRIVE_REMOTE`); a path inside dust, or a folder that contains dust (a loop); the same folder twice (compared after full-path and case folding); a name that is taken gets " 2", " 3". A folder with no audio is added, with the note "no audio files found yet" (a drive can be filled later).
3. **Remove is guarded in four steps**: (a) the name must start with `[ext] ` and hold no separator or `..`; (b) the entry must be a link (Windows: a reparse point with the mount-point or symlink tag; Linux: `lstat` says symlink), a real folder or file is refused; (c) only the link itself is removed (`RemoveDirectoryW` on the junction, `unlink` on the symlink), never a recursive delete; (d) the target is never opened for writing. The list in the config file is not trusted: the rules look at the disk.
4. **Config file** `<home>/extra-folders.conf`, one entry per line, `name<TAB>path`, written through a temporary file. At start `ef_sync` re-creates a missing link when the target exists; if the target is missing the entry stays and is shown as unavailable, nothing is deleted. A name taken by a real folder is shown as blocked, never touched.
5. **Folder picker (Windows)**: `IFileOpenDialog` with `FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM`, on its own thread with its own COM apartment, owner = the window that is in front when it opens (so it works from the norns window and the detached screen window). The result comes back with `call_lua("ext_folder_chosen", path)`, like the file chooser, so the audio and clock threads are not blocked. Linux: `picker_open` is untouched.
6. **Lua**: `_norns.ext_list/add/remove/pick/sync` exist only in norns.exe (NORNS_WINDOWS). Page `core/menu/extra.lua` (SYSTEM > EXTRA FOLDERS): one list, E2 selects, K3 on an entry asks (a warning in plain words), K3 again removes, K2 cancels or goes back; ADD FOLDER is the last row. `ext_sync` runs once at start.
7. **Menu, Windows only** (`#ifdef NORNS_WINDOWS` in `desktop_shell_linux.cc`): hide Import files/folder, Copy samples, the file-dialog tick and the virtual grid/arc/keyboard; add "Extra folders" (opens the page). The Linux menu is byte-for-byte as before.
8. **Tests**: `linux/tests/extfolders_test.c` (POSIX backend: all rules, a real folder of the same name, a target with files that survive, removal with a file open, restart, a script-like reader through the link), run in `run_all.sh`; `windows/ci/extfolders_probe.c` on the Windows runner with the junction backend (a path with a blank and an accented letter, the same cases, plus a reparse-tag check). The picker window cannot be exercised on a runner (nothing to click).

## Not done / cannot be tested without the owner's PC
The picker window itself, a real unplugged drive, a OneDrive-redirected folder, long paths beyond a few hundred characters on a real disk.
