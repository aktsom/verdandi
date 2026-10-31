#!/bin/bash
# linux/scan-fkeys.sh [DUST_CODE_FOLDER]: which of your scripts read the function keys that Verdandi's screen window takes (docs/port/detach-plan.md).
#   F9   detach the screen / bring it back        F11  fullscreen of the screen window        F12  (kept for a later "snap to a whole scale", hidden)
#   Ctrl+M  mute (docs/port/box-style-plan.md): reported as the scripts that test keyboard.ctrl() and name the letter M
#   Ctrl+Shift+M  the MIDI actions on and off (docs/port/midi-actions-plan.md): the scripts that test keyboard.ctrl() and keyboard.shift() and name the letter M
# it only READS the .lua files of the folder (default: <norns home>/dust/code, the norns home as `verdandi` finds it: NORNS_HOME, or ~/Verdandi) and prints
# (and the arc keys 5 6 T Y G H B N, see below) every script that names one of those keys the way norns scripts do (keyboard.code gets "F9", "F11", "F12" as text), the lines it is on, and how many
# scripts read the keyboard at all. nothing is changed.
set -u
dir="${1:-}"
if [ -z "$dir" ]; then
    home="${NORNS_HOME:-}"
    if [ -z "$home" ]; then
        # the home as the launcher finds it: the first line of ~/.config/verdandi/home, else ~/Verdandi
        home="$(head -n 1 "${XDG_CONFIG_HOME:-${HOME:-}/.config}/verdandi/home" 2> /dev/null | tr -d '\r')"
        case "$home" in "~/"*) home="${HOME:-}/${home#\~/}" ;; esac
        [ -n "$home" ] || home="${HOME:-}/Verdandi"
    fi
    dir="$home/dust/code"
fi
[ -d "$dir" ] || { echo "scan-fkeys: $dir is not a folder (give the dust/code folder as the argument)"; exit 1; }
echo "scanning the .lua files under $dir (reading only)"
total=$(find "$dir" -name '*.lua' -type f 2> /dev/null | wc -l)
readers=$(grep -rlE 'keyboard\.(code|char)[[:space:]]*=|function[[:space:]]+keyboard\.(code|char)' --include='*.lua' "$dir" 2> /dev/null | wc -l)
echo "$total .lua files, $readers of them set keyboard.code or keyboard.char"
rc=0
for k in F9 F11 F12; do
    echo
    hits=$(grep -rnE "[\"']${k}[\"']" --include='*.lua' "$dir" 2> /dev/null)
    if [ -z "$hits" ]; then
        echo "$k: no script names it"
    else
        n=$(printf '%s\n' "$hits" | cut -d: -f1 | sort -u | wc -l)
        echo "$k: $n script file(s) name it:"
        printf '%s\n' "$hits" | sed "s|^$dir/||" | sed 's/^/   /' | head -40
        rc=2
    fi
done
# Ctrl+M (mute, docs/port/box-style-plan.md): Verdandi takes it in C, before a script sees it. which scripts test keyboard.ctrl() at all, and which of those name the letter M
echo
ctrl_files=$(grep -rlE 'keyboard\.ctrl[[:space:]]*\(' --include='*.lua' "$dir" 2> /dev/null)
nctrl=0
[ -n "$ctrl_files" ] && nctrl=$(printf '%s\n' "$ctrl_files" | wc -l)
mhits=""
for f in $ctrl_files; do
    h=$(grep -nE "[\"'][mM][\"']" "$f" 2> /dev/null | sed "s|^|$f:|")
    [ -n "$h" ] && mhits="$mhits$h"$'\n'
done
mfiles=0
[ -n "$mhits" ] && mfiles=$(printf '%s' "$mhits" | cut -d: -f1 | sort -u | wc -l)
if [ "$mfiles" = 0 ]; then
    echo "Ctrl+M: $nctrl script file(s) test keyboard.ctrl(); none of them name the letter M"
    mrc=0
else
    echo "Ctrl+M: $nctrl script file(s) test keyboard.ctrl(); $mfiles of them name the letter M:"
    printf '%s' "$mhits" | sed "s|^$dir/||" | sed 's/^/   /' | head -40
    mrc=2
fi
# Ctrl+Shift+M (the MIDI actions on and off, docs/port/midi-actions-plan.md): Verdandi takes it in C too. which scripts test keyboard.ctrl() and keyboard.shift() and name the letter M
echo
both_files=$(grep -rlE 'keyboard\.ctrl[[:space:]]*\(' --include='*.lua' "$dir" 2> /dev/null | xargs -r grep -lE 'keyboard\.shift[[:space:]]*\(' 2> /dev/null)
nboth=0
[ -n "$both_files" ] && nboth=$(printf '%s\n' "$both_files" | wc -l)
shits=""
for f in $both_files; do
    h=$(grep -nE "[\"'][mM][\"']" "$f" 2> /dev/null | sed "s|^|$f:|")
    [ -n "$h" ] && shits="$shits$h"$'\n'
done
sfiles=0
[ -n "$shits" ] && sfiles=$(printf '%s' "$shits" | cut -d: -f1 | sort -u | wc -l)
if [ "$sfiles" = 0 ]; then
    echo "Ctrl+Shift+M: $nboth script file(s) test both keyboard.ctrl() and keyboard.shift(); none of them name the letter M"
    src=0
else
    echo "Ctrl+Shift+M: $nboth script file(s) test both keyboard.ctrl() and keyboard.shift(); $sfiles of them name the letter M:"
    printf '%s' "$shits" | sed "s|^$dir/||" | sed 's/^/   /' | head -40
    src=2
fi
# the arc keys (docs/port/arc-plan.md 5.3): 5 6 T Y G H B N turn the encoders of the virtual arc. in the norns window they are taken only while no script reads the keyboard, so a script that does keeps them; only the
# arc window takes them for itself. which scripts that READ the keyboard (they set keyboard.code or keyboard.char) name one of them, as keyboard.code gets "5" or "T" and keyboard.char gets "h" or "t"
echo
reader_files=$(grep -rlE 'keyboard\.(code|char)[[:space:]]*=|function[[:space:]]+keyboard\.(code|char)' --include='*.lua' "$dir" 2> /dev/null)
ahits=""
for f in $reader_files; do
    h=$(grep -nE "[\"'](5|6|T|Y|G|H|B|N|t|y|g|h|b|n)[\"']" "$f" 2> /dev/null | sed "s|^|$f:|")
    [ -n "$h" ] && ahits="$ahits$h"$'\n'
done
afiles=0
[ -n "$ahits" ] && afiles=$(printf '%s' "$ahits" | cut -d: -f1 | sort -u | wc -l)
if [ "$afiles" = 0 ]; then
    echo "Arc keys 5 6 T Y G H B N: no script that reads the keyboard names them"
    arc_rc=0
else
    echo "Arc keys 5 6 T Y G H B N: $afiles script file(s) that read the keyboard name them:"
    printf '%s' "$ahits" | sed "s|^$dir/||" | sed 's/^/   /' | head -40
    arc_rc=2
fi
echo
if [ $rc = 0 ]; then
    echo "RESULT none of your scripts name F9, F11 or F12: nothing is given up"
else
    echo "RESULT some scripts name those keys (above): in the screen window F9 and F11 are taken by Verdandi on the Linux desktop; F12 is not used yet"
fi
if [ $mrc = 0 ]; then
    echo "RESULT no script combines keyboard.ctrl with the letter M: Ctrl+M (mute) takes nothing"
else
    echo "RESULT Ctrl+M (mute) may be read by the script(s) above: Verdandi takes Ctrl+M for mute before a script sees it (the owner can choose Ctrl+Shift+M instead)"
fi
if [ $src = 0 ]; then
    echo "RESULT no script combines keyboard.ctrl and keyboard.shift with the letter M: Ctrl+Shift+M (MIDI actions on/off) takes nothing"
else
    echo "RESULT Ctrl+Shift+M (MIDI actions on/off) may be read by the script(s) above: Verdandi takes it before a script sees it (another key can be chosen)"
fi
if [ $arc_rc = 0 ]; then
    echo "RESULT arc keys: no script reads them: nothing is given up"
else
    echo "RESULT arc keys: scripts above read some of them: in the norns window those keys stay the script's while it runs (nothing is taken from it); only the arc window takes them, and ARC KEYS in SYSTEM > MIDI MAP can turn the norns window's use off"
fi
exit 0
