# Scripts that run shell commands naming a norns path (KNOWN-ISSUES item 22)

Made with `linux/scan-shell-paths.py` on the catalog clone (351 scripts, `macos/docs/catalog-scan.json`) and on the 18 scripts the owner has installed. A script is listed when one Lua line has a shell command or a call that runs one, together with `/home/we` or `_path.*` on the *same line*; a command built on one line and run on another is not found, so the list is a lower bound.

Kinds: **reads output** (`os.capture`, `util.os_capture`, `io.popen`, `norns.system_cmd`: the answer comes back, so what is in it matters; since item 22 a command's stderr is no longer part of it), **runs** (`os.execute`), **builds** (a command string, the call is elsewhere).

## The owner's installed scripts (18): 4 run such commands

| script | kind | where |
|---|---|---|
| cheat_codes_2 | runs | cheat_codes_2.lua:189; cheat_codes_2.lua:242; cheat_codes_2.lua:245; cheat_codes_2.lua:6381 |
| dronecaster | reads output | dronecaster.lua:302 |
| granchild | runs | lib/granchild.lua:660 |
| nb_mxsynths | runs | lib/mod.lua:444 |

mx.samples is not among the 18 (the owner was trying it). The other 14 installed scripts name no path in a shell command on one line.

## The catalog: 39 of 351 scripts

| script | kinds | lines |
|---|---|---|
| 21echoes/pedalboard | builds, runs | 5 |
| Mendrzec/impact | runs | 1 |
| MentalSandal/nice-tapes | reads output, runs | 3 |
| TuesdayNightMachines/nmMelodyMagic | runs | 1 |
| awwaiid/repl-looper | runs | 1 |
| danielrigler/twins | reads output | 1 |
| dndrks/cheat_codes_2 | runs | 4 |
| loudnumbers/loudnumbers_norns | reads output | 1 |
| monome-community/nc03-ds | runs | 2 |
| norns-study-group/pirate-radio | builds, reads output | 3 |
| northern-information/dronecaster | reads output | 1 |
| northern-information/goldeneye | reads output | 1 |
| northern-information/u | reads output | 1 |
| northern-information/yggdrasil | reads output | 1 |
| robmckinnon/pitfalls | reads output | 3 |
| ryleelyman/faeng | reads output | 2 |
| schollz/amen | runs | 3 |
| schollz/amenbreak | builds, runs | 9 |
| schollz/downtown | builds | 1 |
| schollz/graintopia | builds, runs | 4 |
| schollz/granchild | runs | 1 |
| schollz/internorns | runs | 4 |
| schollz/kolor | builds, runs | 2 |
| schollz/makebreakbeat | reads output, runs | 3 |
| schollz/mx.samples | builds, reads output | 4 |
| schollz/o-o-o | runs | 2 |
| schollz/paracosms | runs | 12 |
| schollz/rachim | runs | 3 |
| schollz/sampswap | runs | 2 |
| schollz/supertonic | reads output, runs | 6 |
| schollz/thirtythree | runs | 2 |
| schollz/warmreload | runs | 1 |
| schollz/zxcvbn | builds, reads output, runs | 37 |
| skibu/taweeet | runs | 1 |
| sonocircuit/nb_mxsynths | runs | 1 |
| tapecanvas/nornsfetch | reads output | 3 |
| tgk/rangl | runs | 1 |
| toneburst/bline | runs | 4 |
| zjb-s/oilcan | runs | 1 |

## Shell scripts that contain `/home/we` themselves (not rewritten: item 22, limits)

A command is translated, the *contents* of a script it runs are not. In the catalog clone these `.sh` files name `/home/we`: `schollz/graintopia lib/oscnotify/run.sh`, `schollz/warmreload run.sh`, `schollz/zxcvbn lib/oscnotify/run.sh`, `schollz/amenbreak lib/oscnotify/run.sh`, `schollz/amenbreak lib/install.sh`, `schollz/sampswap lib/install.sh`, `seajaysec/ingenue install.sh`, `awwaiid/repl-looper util/sync.sh`.

