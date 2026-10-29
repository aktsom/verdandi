#!/bin/bash
# shell commands run by scripts on the Linux desktop (docs/port/KNOWN-ISSUES.md item 22): os.capture-style io.popen reads, io.popen, os.execute and norns.system_cmd with the virtual /home/we in the
# command, in a real headless norns (linux/tests/norns_probe.sh: Xvfb, dummy jackd, the real launcher and sidecar).
#   - the virtual path reaches the shell as the real norns home (existing folder: the file names come back with /home/we, a folder with spaces works, /home/weird and /tmp/home/we are left alone)
#   - a command's stderr is not part of what the script reads (mx.samples: "ls <missing>/*.wav" must not give a string that contains ".wav"); it is in the log; "2>&1" in the command and
#     NORNS_CAPTURE_STDERR=1 still merge it
#   - a download-style sequence as mx.samples does it (mkdir -p, curl -L -o <zip> <url> with a stand-in curl, unzip -d, rm) works inside /home/we/dust/audio and the files are in the real home
#   - mx.samples itself (github.com/schollz/mx.samples, cloned: MX_SAMPLES_DIR=<a clone> avoids the network): update_uilist() shows "get?" for the packs that are not there and not for the one that is;
#     download() with the stand-in curl makes the pack count as downloaded
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap '[ -n "${KEEP_DIR:-}" ] && cp -r "$T" "$KEEP_DIR"; rm -rf "${T:?}"' EXIT
FAIL=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAIL=1; }
command -v xdotool > /dev/null && command -v sclang > /dev/null && command -v zip > /dev/null && command -v unzip > /dev/null && command -v curl > /dev/null || { echo "SKIP: xdotool, sclang, zip, unzip or curl missing"; exit 0; }

# a stand-in curl: "curl -L -o <file> <url>" copies a prepared zip to <file> and records its arguments (no network)
mkdir -p "$T/stub" "$T/zipsrc"
cat > "$T/stub/curl" << STUB
#!/bin/sh
out=""; prev=""
for a in "\$@"; do [ "\$prev" = -o ] && out="\$a"; prev="\$a"; done
echo "curl \$*" >> "$T/curl.log"
[ -n "\$out" ] && cp "$T/pack.zip" "\$out"
STUB
chmod +x "$T/stub/curl"
echo "fake sample" > "$T/zipsrc/c4.wav"; echo "fake sample" > "$T/zipsrc/d4.wav"
(cd "$T/zipsrc" && zip -q "$T/pack.zip" c4.wav d4.wav)

SRC="${MX_SAMPLES_DIR:-}"
if [ -z "$SRC" ]; then
    SRC="$T/clone"
    timeout 90 git clone -q --depth 1 https://github.com/schollz/mx.samples "$SRC" 2> /dev/null || SRC=""
fi
[ -n "$SRC" ] && [ ! -f "$SRC/mx.samples.lua" ] && SRC=""
[ -n "$SRC" ] || echo "(mx.samples could not be fetched: its part is skipped)"

mkhome() { # name
    local H="$T/$1"
    mkdir -p "$H/dust/audio/mx.samples/Have" "$H/dust/audio/Has Space" "$H/dust/code" "$H/dust/data"
    touch "$H/dust/audio/mx.samples/Have/a.wav" "$H/dust/audio/mx.samples/Have/b.wav" "$H/dust/audio/Has Space/s p.wav"
    ln -s "$REPO" "$H/norns"
}
mkhome home
H="$T/home"
[ -n "$SRC" ] && { cp -a "$SRC" "$H/dust/code/mx.samples"; mkdir -p "$H/dust/audio/mx.samples/12string_piano"; touch "$H/dust/audio/mx.samples/12string_piano/c4.wav"; }

{
    echo "#sleep 5"
    cat << 'LUA'
function oc(cmd, raw) local f = assert(io.popen(cmd, 'r')) local s = assert(f:read('*a')) f:close() if raw then return s end s = string.gsub(s, '^%s+', '') s = string.gsub(s, '%s+$', '') s = string.gsub(s, '[\n\r]+', ' ') return s end
print("R missing [" .. oc("ls /home/we/dust/audio/mx.samples/Nope/*.wav") .. "]")
print("R have [" .. oc("ls /home/we/dust/audio/mx.samples/Have/*.wav") .. "]")
print("R spaces [" .. oc("ls '/home/we/dust/audio/Has Space/'") .. "]")
print("R spaces_dq [" .. oc('ls "/home/we/dust/audio/Has Space/"*.wav') .. "]")
print("R weird [" .. oc("echo /home/weird/x /tmp/home/we/x /home/we /home/we/ '/home/we/y' \"/home/we/z\" /home/we.d") .. "]")
print("R merged [" .. oc("ls /home/we/dust/audio/mx.samples/Nope/*.wav 2>&1") .. "]")
local n = 0 for l in io.popen("ls /home/we/dust/audio/mx.samples/Have/"):lines() do n = n + 1 end print("R popen_lines [" .. n .. "]")
local ok, how, code = os.execute("ls /home/we/dust/audio/mx.samples/Have/a.wav > /dev/null") print("R exec_have [" .. tostring(ok) .. " " .. tostring(how) .. " " .. tostring(code) .. "]")
local ok2, how2, code2 = os.execute("ls /home/we/dust/audio/mx.samples/Nope/ > /dev/null") print("R exec_missing [" .. tostring(ok2) .. " " .. tostring(how2) .. " " .. tostring(code2) .. "]")
norns.system_cmd("ls /home/we/dust/audio/mx.samples/Have/*.wav", function(out) print("R syscmd [" .. out:gsub("\n", " ") .. "]") end)
norns.system_cmd("ls /home/we/dust/audio/mx.samples/Nope/*.wav", function(out) print("R syscmd_missing [" .. out .. "]") end)
LUA
    echo "#sleep 3"
    cat << LUA
id = "Zed"
dir = _path.audio .. "mx.samples/" .. id
os.execute("mkdir -p " .. dir)
os.execute("curl -L -o " .. dir .. "/download.zip https://example.invalid/" .. id .. ".zip")
os.execute("unzip " .. dir .. "/download.zip -d " .. dir .. "/")
os.execute("rm " .. dir .. "/download.zip")
print("R seq [" .. oc("ls " .. dir .. "/") .. "]")
LUA
    if [ -n "$SRC" ]; then
        cat << 'LUA'
norns.script.load("code/mx.samples/mx.samples.lua")
LUA
        echo "#sleep 15"
        cat << 'LUA'
update_uilist()
g, h = 0, 0
for _, s in ipairs(items) do if s:find(" - get?", 1, true) then g = g + 1 else h = h + 1 end end
print("R mx_counts [get=" .. g .. " have=" .. h .. " total=" .. #items .. "]")
print("R mx_first [" .. items[1] .. "]")
print("R mx_flags [" .. tostring(available_instruments[1].downloaded) .. " " .. tostring(available_instruments[2].downloaded) .. "]")
download(available_instruments[2].id)
update_uilist()
print("R mx_after [" .. items[2] .. "|" .. tostring(available_instruments[2].downloaded) .. "]")
LUA
    fi
    echo "#sleep 2"
    echo 'print("PROBE shell done")'
} > "$T/probe.lua"

boot() { # name, env...
    local name="$1"; shift
    env NORNS_HOME="$T/$name" PATH="$T/stub:$PATH" "$@" "$REPO/linux/tests/norns_probe.sh" "$T/probe.lua" "$T/$name.log" > /dev/null 2>&1
}
boot home
L="$T/home.log"
r() { sed -n "s/^R $1 \[\(.*\)\]\s*$/\1/p" "$L" | tail -n 1; }

echo "== the virtual /home/we reaches the shell as the real home"
[ "$(r have)" = "/home/we/dust/audio/mx.samples/Have/a.wav /home/we/dust/audio/mx.samples/Have/b.wav" ] && ok "an existing folder: the file names come back with /home/we" || bad "have: '$(r have)'"
[ "$(r spaces)" = "s p.wav" ] && ok "a folder with spaces (quoted)" || bad "spaces: '$(r spaces)'"
[ "$(r spaces_dq)" = "/home/we/dust/audio/Has Space/s p.wav" ] && ok "double quotes and a glob after the quote" || bad "spaces_dq: '$(r spaces_dq)'"
[ "$(r weird)" = "/home/weird/x /tmp/home/we/x /home/we /home/we/ /home/we/y /home/we/z /home/we.d" ] && ok "/home/weird, /tmp/home/we and /home/we.d untouched; /home/we alone, with a slash and in quotes round-trip" || bad "weird: '$(r weird)'"
[ "$(r popen_lines)" = 2 ] && ok "io.popen lines" || bad "popen_lines: '$(r popen_lines)'"
[ "$(r exec_have)" = "true exit 0" ] && ok "os.execute on an existing file: true exit 0" || bad "exec_have: '$(r exec_have)'"
case "$(r exec_missing)" in "nil exit 2") ok "os.execute on a missing folder: nil exit 2" ;; *) bad "exec_missing: '$(r exec_missing)'" ;; esac
[ "$(r syscmd)" = "/home/we/dust/audio/mx.samples/Have/a.wav /home/we/dust/audio/mx.samples/Have/b.wav " ] && ok "norns.system_cmd" || bad "syscmd: '$(r syscmd)'"

echo "== a command's stderr is not what the script reads (item 22)"
[ "$(r missing)" = "" ] && ok "os.capture of ls on a missing folder is empty (no \".wav\" in it, mx.samples shows get?)" || bad "missing: '$(r missing)'"
[ "$(r syscmd_missing)" = "" ] && ok "norns.system_cmd: the same" || bad "syscmd_missing: '$(r syscmd_missing)'"
case "$(r merged)" in *"cannot access"*) ok "a command that says 2>&1 itself still gets its error text (shown with /home/we)" ;; *) bad "merged: '$(r merged)'" ;; esac
case "$(r merged)" in *"$T"*) bad "the real path leaked into the answer: $(r merged)" ;; *) ok "no real path in the answers" ;; esac
grep -aqE "^ls: cannot access .*mx.samples/Nope" "$T/home.log" && ok "the complaint went to the program's own log output (norns.log in a normal start), not to the script" || bad "no complaint in the log output"

echo "== a download as mx.samples does it"
[ "$(r seq)" = "c4.wav d4.wav" ] && ok "mkdir -p, curl -L -o (stand-in), unzip -d, rm: the pack is there and the zip is gone" || bad "seq: '$(r seq)'"
ls "$H/dust/audio/mx.samples/Zed/c4.wav" > /dev/null 2>&1 && [ ! -e "$H/dust/audio/mx.samples/Zed/download.zip" ] && ok "in the real home, nothing in a real /home/we" || bad "files not in the real home"
grep -q "curl -L -o $H/dust/audio/mx.samples/Zed/download.zip" "$T/curl.log" 2> /dev/null && ok "curl was given the real path" || bad "curl log: $(cat "$T/curl.log" 2> /dev/null)"
[ -e /home/we ] && bad "a real /home/we exists on this machine (the test cannot show that nothing was written there)"

if [ -n "$SRC" ]; then
    echo "== mx.samples itself"
    TOTAL="$(grep -c '^  {name=' "$SRC/mx.samples.lua")"
    [ "$(r mx_counts)" = "get=$((TOTAL - 1)) have=1 total=$TOTAL" ] && ok "update_uilist: get? on $((TOTAL - 1)) packs, none on the one that is there" || bad "mx_counts: '$(r mx_counts)' (packs: $TOTAL)"
    case "$(r mx_first)" in *"12string piano"*) case "$(r mx_first)" in *"get?"*) bad "mx_first: '$(r mx_first)'" ;; *) ok "the present pack has no get?" ;; esac ;; *) bad "mx_first: '$(r mx_first)'" ;; esac
    [ "$(r mx_flags)" = "true false" ] && ok "downloaded flags: present true, absent false" || bad "mx_flags: '$(r mx_flags)'"
    case "$(r mx_after)" in *"get?"*) bad "mx_after: '$(r mx_after)'" ;; *"|true") ok "after download() the pack counts as downloaded (stand-in curl)" ;; *) bad "mx_after: '$(r mx_after)'" ;; esac
fi

echo "== NORNS_CAPTURE_STDERR=1 brings the merge back"
printf '#sleep 5\nlocal f = io.popen("ls /home/we/dust/nope/*.wav") print("R merged_on [" .. f:read("*a"):gsub("\\n", " ") .. "]")\n#sleep 1\n' > "$T/probe.lua"
mkhome home2
boot home2 NORNS_CAPTURE_STDERR=1
L="$T/home2.log"
case "$(r merged_on)" in *"cannot access"*) ok "with the variable the error text is in the answer again" ;; *) bad "merged_on: '$(r merged_on)'" ;; esac

[ $FAIL = 0 ] && echo "script_shell_test: all passed"
exit $FAIL
