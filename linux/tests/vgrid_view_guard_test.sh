#!/bin/bash
# M41 (docs/port/phase-m41.md): the virtual grid's new controls sit behind VGRID_ROTATE (= NORNS_LINUX_DESKTOP and not NORNS_WINDOWS): the macOS build and the Windows build compile none of it, and
# the Windows virtual grid stays switched off. read from the sources.
cd "$(dirname "$0")/../.." || exit 1
bad=0
fail() { echo "FAIL: $*"; bad=1; }
ok() { echo "ok   $*"; }
S=matron/src/platform/macos
grep -q '^#if defined(NORNS_LINUX_DESKTOP) && !defined(NORNS_WINDOWS)\( && !defined(VGRID_TEST_NO_ROTATE)\)\?$' $S/vgrid_skin.h && grep -q '#define VGRID_ROTATE 1' $S/vgrid_skin.h && ok "VGRID_ROTATE is defined for the Linux desktop only" || fail "VGRID_ROTATE is not behind the Linux desktop guard"
# every use of the new names in the shared files is inside an #ifdef VGRID_ROTATE: count the lines that mention them outside
for f in $S/vgrid_skin.c $S/sdl_bridge.cc; do
    awk -v file="$f" '
        /^[ \t]*#[ \t]*if(def)?[ \t]+VGRID_ROTATE/ { depth_rot++; stack[++sp] = "rot"; next }
        /^[ \t]*#[ \t]*if/ { stack[++sp] = "other"; next }
        /^[ \t]*#[ \t]*else/ { if (stack[sp] == "rot") { stack[sp] = "notrot" } else if (stack[sp] == "notrot") { stack[sp] = "rot" } next }
        /^[ \t]*#[ \t]*endif/ { sp--; next }
        {
            inrot = 0
            for (i = 1; i <= sp; i++) if (stack[i] == "rot") inrot = 1
            if (!inrot && ($0 ~ /vgv_|VGRID_HELD_PENDING|grid_multi|vgrid_skin_geom_rot|vgrid_skin_units_rot|grid_rotate|grid_rot[^a-z_]/) && $0 !~ /^[ \t]*(\/\/|\*|\/\*)/) { print file ":" NR ": " $0; found = 1 }
        }
        END { exit found }' "$f" || fail "$f uses the new names outside VGRID_ROTATE"
done
[ "$bad" = 0 ] && ok "the shared files use the new names only inside VGRID_ROTATE"
grep -q 'not on Windows (switched off)' matron/src/platform/windows/vgrid_device_win.c && ok "the Windows virtual grid is still switched off" || fail "the Windows switch-off line is gone"
git diff --quiet HEAD~0 -- matron/src/platform/windows/vgrid_device_win.c 2> /dev/null && ok "vgrid_device_win.c has no uncommitted change"
[ "$bad" = 0 ] && echo "vgrid_view_guard_test: all passed" || { echo "vgrid_view_guard_test: failed"; exit 1; }
