# Extra sample folders and a shorter right-click menu (proposal, no code)

Status: investigation and proposal only. Nothing here is built. Waiting for the owner's decision.

## 1. What the right-click menu items do today (Linux port)

- **Import files / Import folder**: open the system file dialog (zenity) and hand the chosen paths to the same code as a drag-and-drop.
  - Audio files (wav, wave, aif, aiff, aifc, flac, ogg, mp3): *linked* into `dust/audio/<DUST_LINK_DIR>/` (a symlink, the original stays where it is) or, with the copy option / Shift, *copied* into `dust/audio/`.
  - A folder that holds audio: linked or copied the same way, as one folder.
  - A folder with a `.lua` at its top, or a single `.lua`: *copied* into `dust/code/` (scripts are always copied). That is how audio and scripts are told apart: by extension, and for a folder by whether a `.lua` sits at the top.
  - Name clashes get " 2", " 3", ... Temporary files (from a browser, an archive) are copied, because the link would break.
- **Copy samples into dust** (a tick): switches the audio import from "link" to "copy". Link is instant and uses no space but breaks if the original moves; copy is self-contained. Same as holding Shift on a drop.
- **Open the file dialog when a script loads a file** (a tick): when a script asks for a sample, show the system dialog instead of the norns browser. The browser (fileselect) stays the default.
- The other items (grid / arc / keyboard windows, screenshot, GIF, show in file manager, input MIC/SYS/OFF) are unrelated to this proposal.

On Windows the import items are not built yet (plain message now). On Windows `dust_import_kind` always says "skip".

## 2. How the norns browser finds folders

- `lua/lib/fileselect.lua`: a script calls `fileselect.enter(root, callback)`; the tape page uses `fileselect.enter(_path.audio, ...)` (`lua/core/menu/tape.lua`, `open_play_fileselect`).
- The list is made by `util.scandir(dir)`: on Windows `_norns.listdir` (native, wide API, UTF-8, hides dot and hidden files, `ls -p` shape), elsewhere `ls -pL`.
- The browser only goes *down* from the root and back up to that root; `..` stops at the root. So the root a script passes is the whole world it can see.
- Virtual `/home/we` (`lua/core/virtual_home.lua`) maps `/home/we/dust` to the real dust folder; paths are translated by `to_real` before any file call. Anything under a real folder reached by a link inside dust is read and played like any other file (`audio.file_info`, `tape_play_open`, softcut buffer reads all take the translated path).
- Long paths: `_norns.listdir` buffers are MAX_PATH*2 wide chars, so paths beyond about 260 characters fail without the `\\?\` prefix (needs a small change). Non-ASCII is fine (UTF-8 to wide).

## 3. Options for extra folders

| Option | How | Pros | Cons | Cost |
|---|---|---|---|---|
| A. Copy files into dust by hand | Windows Explorer into `dust\audio\` | Zero code, always works, works for every script | Duplicates big libraries, owner must do it each time | none |
| B. Links under dust (Linux symlink, Windows junction) | A setting creates `dust/audio/<marker>name` pointing at the folder | Browser, scripts, tape all work unchanged; no listing change | Windows symlinks need privilege, junctions work without; junction targets must be local drives; a deleted target leaves a dead entry | small (Linux: symlink; Windows: `mklink /J` via API) |
| C. Listing change in fileselect | When the browser lists `_path.audio`, append the extra folders with a marker such as `+ Name/` | Nothing created on disk; marker is obvious | Only fileselect and tape page see them; scripts that scan folders themselves do not; paths outside `/home/we` need a new virtual root; every consumer of the path must understand it | medium |
| D. Mapping in virtual_home | Map `/home/we/extra/<name>` to the real folder | Scripts could open by path | New virtual root, every PATH_FUNCTIONS entry must translate it, shell quoting contexts | medium to large |

Recommendation: **B (junction on Windows, symlink on Linux)**, with the marker in the *name* of the link (for example `[ext] Samples`), so the browser, the tape page and any script show them next to the normal folders with no listing change. It is the same mechanism the Linux importer already uses (`audio/<DUST_LINK_DIR>`), so it works identically on Linux. If the owner only has a few folders and rarely adds more, **A is a perfectly good answer**: copy the files once. B only earns its cost if folders change or are large.

Caveats to state: a junction cannot point to a network share; removing a folder in the setting must delete only the junction, never the target (the code must remove the link itself, not recurse); a link whose target is gone is hidden or flagged.

Works the same on Linux: yes, with a symlink in place of a junction.

## 4. Where to set the folders

Keep the norns style: a single scrolling list, E2 selects, E3 changes, K3 applies, K2 back.

- Best fit: a new **SYSTEM > EXTRA FOLDERS** page (one list: `1: C:\Samples`, `2: (empty)`, ...). K3 on a line opens the *native folder picker* (a Windows picker is needed and does not exist yet in this build) to set or clear it. Stored in a small config file (`ui.conf` next to the existing keys), applied at start and on K3.
- Alternative with no new picker: a plain text file `extra-folders.txt` (one path per line) in the Verdandi folder, opened from a menu item. Simplest to build, less friendly.
- Not recommended: a right-click item per folder; it grows the menu.

## 5. Right-click menu: keep, hide or remove on Windows

Recommendation (owner said most items are not needed):

- **Keep**: Screenshot, GIF, input MIC/SYS/OFF (when the Windows input exists), Show in file manager.
- **Hide for now** (not built on Windows): Import files, Import folder, Copy samples into dust, Open the file dialog when a script loads a file, virtual grid / arc / keyboard (until built).
- **Remove**: nothing from the shared code; hide via the Windows build only so Linux does not change.

If extra folders (option B) are built, Import files / folder and the two ticks stay hidden for good on Windows, and the setting above replaces them.

## 6. What could not be tested
No Windows machine here: junction creation, native folder picker and OneDrive/non-ASCII paths all need the owner's PC. Everything above is read from code.
