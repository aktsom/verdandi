#!/usr/bin/env bash
# windows/ci/build-sc3plugins.sh (M7): the SuperCollider plug-in packs for Windows x86-64, built with MSVC against the headers of SuperCollider 3.14.1 (the version Verdandi ships): the WHOLE
# sc3-plugins collection (GPL-2.0-or-later), mi-UGens (v7b1, MIT/GPL parts: licence files are copied) and, when NAMAMP_URL is given, NamAmp. Nothing here stops at the first failure: every plug-in
# directory is built on its own with `ninja -k 0`, and the result is a table (BUILT / FAILED / NOT BUILT) in $OUT/m7-report.txt that says what compiled and the first error of what did not.
# the output tree $OUT/seed/<pack>/ is what the package job puts in extensions-seed\ (docs/port/phase-m7.md). run from Git Bash with the MSVC environment and cmake + ninja on PATH.
#   SC_TAG         Version-3.14.1       SC3P_TAG   Version-3.13.0 (falls back to the default branch)    MIUGENS_REF  main
#   NAMAMP_URL     git URL of NamAmp (empty: skipped, the owner has to name the source)             NAMAMP_REF   (default branch)
#   WORK, OUT      work folder and output folder
set -u
SC_TAG="${SC_TAG:-Version-3.14.1}"
SC3P_TAG="${SC3P_TAG:-Version-3.13.0}"
MIUGENS_REF="${MIUGENS_REF:-main}"
WORK="${WORK:-$PWD/m7-work}"
OUT="${OUT:-$PWD/m7-out}"
mkdir -p "$WORK" "$OUT/seed" "$OUT/logs"
REPORT="$OUT/m7-report.txt"
: > "$REPORT"
say() { echo "$*" | tee -a "$REPORT"; }

clone() { # url ref dir
    [ -d "$3/.git" ] && return 0
    git clone -c core.autocrlf=false --depth 1 --branch "$2" --recurse-submodules --shallow-submodules "$1" "$3" 2>&1 \
        || git clone -c core.autocrlf=false --depth 1 --recurse-submodules --shallow-submodules "$1" "$3" 2>&1
}

# the headers only: SuperCollider's plug-in interface (common/ and include/plugin_interface, include/server, include/common)
SC_SRC="$WORK/sc-src"
clone https://github.com/supercollider/supercollider.git "$SC_TAG" "$SC_SRC" > "$OUT/logs/clone-sc.log" 2>&1 || { say "FAIL: could not clone SuperCollider $SC_TAG"; exit 1; }

# FFTW (single precision, the prebuilt DLL package with an import library made from its .def, as build-sc.sh does): several sc3-plugins directories need it
FFTW_DIR="$WORK/fftw"
mkdir -p "$FFTW_DIR"
(
    cd "$FFTW_DIR" || exit 1
    curl -fL --retry 3 -o fftw.zip https://fftw.org/pub/fftw/fftw-3.3.5-dll64.zip && 7z x fftw.zip -y > /dev/null && lib.exe /machine:x64 /def:libfftw3f-3.def > /dev/null
) > "$OUT/logs/fftw.log" 2>&1
if [ -f "$FFTW_DIR/libfftw3f-3.lib" ]; then
    FFTW_ARGS=(-DFFTW3F_INCLUDE_DIR="$FFTW_DIR" -DFFTW3F_LIBRARY="$FFTW_DIR/libfftw3f-3.lib" -DFFTW3_INCLUDE_DIR="$FFTW_DIR" -DCMAKE_PREFIX_PATH="$FFTW_DIR")
    say "FFTW: found ($FFTW_DIR)"
else
    FFTW_ARGS=()
    say "FFTW: NOT available (see logs/fftw.log): directories that need it will fail"
fi

# build_pack <name> <source dir> <extra cmake args...>: configure + `ninja -k 0`; the .scx files and the class files go to $OUT/seed/<name>
build_pack() {
    local name="$1" src="$2" bld="$WORK/build-$1" log="$OUT/logs/build-$1.log"
    shift 2
    say "== $name: configure"
    if ! cmake -S "$src" -B "$bld" -G Ninja -DCMAKE_BUILD_TYPE=Release -DSC_PATH="$SC_SRC" -DSUPERNOVA=OFF "${FFTW_ARGS[@]}" "$@" > "$OUT/logs/configure-$name.log" 2>&1; then
        say "$name: CONFIGURE FAILED. the errors:"; grep -B1 -A8 "CMake Error" "$OUT/logs/configure-$name.log" | head -n 60 | tee -a "$REPORT"; tail -n 5 "$OUT/logs/configure-$name.log" | tee -a "$REPORT"
        return 1
    fi
    say "== $name: build (ninja -k 0)"
    ninja -C "$bld" -k 0 > "$log" 2>&1
    local rc=$?
    say "$name: ninja exit $rc"
    if [ "$rc" -ne 0 ] && ! grep -q "^FAILED: " "$log"; then say "$name: ninja stopped without a failed target. last lines:"; tail -n 25 "$log" | tee -a "$REPORT"; fi
    # the targets that failed, with their first error
    grep -E "^FAILED: " "$log" | sed 's/^FAILED: //' | sort -u > "$OUT/logs/failed-$name.txt"
    local nfail
    nfail=$(wc -l < "$OUT/logs/failed-$name.txt")
    local dest="$OUT/seed/$name"
    mkdir -p "$dest/plugins"
    find "$bld" -name '*.scx' -exec cp {} "$dest/plugins/" \;
    local built
    built=$(find "$dest/plugins" -name '*.scx' | wc -l)
    say "$name: $built plug-in files (.scx) built, $nfail targets failed"
    while read -r t; do
        [ -n "$t" ] || continue
        say "  FAILED target: $t"
        # the first error line of that target
        grep -F -A12 "FAILED: $t" "$log" | grep -m 1 -E "error C[0-9]+|fatal error|error LNK[0-9]+|undefined" | sed 's/^/    first error: /' | tee -a "$REPORT"
    done < "$OUT/logs/failed-$name.txt"
    return 0
}

# --- begin pack checks (linux/tests/pack_check_test.sh runs this part on Linux)
PACK_LAYOUT=2 # the layout of a pack folder: bump it when the folder is arranged differently (it goes into PACK-ID.txt, which makes the launcher replace an older copy)

# all .sc text of a folder without comments (a class that appears twice inside a block comment is not defined twice)
sc_text() { # dir...
    # one file at a time: a file without a final newline must not glue its last line to the first line of the next one
    # shellcheck disable=SC2016
    find "$@" -name '*.sc' -print0 2> /dev/null | xargs -0 perl -0777 -ne 's{/\*.*?\*/}{}gs; s{//[^\n]*}{}g; print $_, "\n"' 2> /dev/null
}
class_names() { sc_text "$@" | grep -oE '^[[:space:]]*[A-Z][A-Za-z0-9_]*[[:space:]]*(:|\{|\[)' | sed -E 's/[[:space:]]*(:|\{|\[)$//; s/^[[:space:]]*//' | sort; }

# finish_pack <name> <unit source dir> <revision source dir>: the checks of a pack and its marker.
#   - UNITS.txt: the UGen names the plug-in files define (from the sources: DefineSimpleUnit(Name), DefineDtorUnit(Name), ..., fDefineUnit)("Name"))
#   - every unit has to have a class, in the pack or in SuperCollider's own class library: the ones that do not are listed (an engine that calls such a UGen stops with "Class 'X' not found")
#   - no class name is defined twice in the pack (comments are not counted)
#   - PACK-ID.txt: <revision>-L<layout>, written only for a pack that has plug-in files AND class files: the launcher copies a pack that has this marker and replaces its own older copy when it differs
finish_pack() {
    local name="$1" unitsrc="$2" revsrc="$3" dest="$OUT/seed/$1" scx classes missing dup rev
    [ -d "$dest" ] || return 0
    scx=$(find "$dest" -name '*.scx' | wc -l)
    classes=$(find "$dest" -name '*.sc' | wc -l)
    { grep -rhoE 'Define[A-Za-z]*Unit\(\s*[A-Za-z0-9_]+' "$unitsrc" --include='*.cpp' --include='*.h' --include='*.hpp' 2> /dev/null | sed -E 's/.*\(\s*//';
      grep -rhoE 'fDefineUnit\)\(\s*"[A-Za-z0-9_]+"' "$unitsrc" --include='*.cpp' 2> /dev/null | sed -E 's/.*"([^"]+)"/\1/'; } | grep -E '^[A-Z]' | grep -vE '^(Name|Unit|Class)$' | sort -u > "$dest/UNITS.txt"
    class_names "$dest" "$SC_SRC/SCClassLibrary" | sort -u > "$OUT/logs/known-classes-$name.txt"
    missing=$(comm -23 "$dest/UNITS.txt" "$OUT/logs/known-classes-$name.txt" | tr '\n' ' ')
    class_names "$dest" | uniq -d | tr '\n' ' ' > "$OUT/logs/duplicate-classes-$name.txt"
    dup=$(cat "$OUT/logs/duplicate-classes-$name.txt")
    say "$name: $scx plug-in files, $classes class files, $(wc -l < "$dest/UNITS.txt") UGen names in the sources"
    if [ -n "$missing" ]; then say "$name: UGENS WITHOUT A CLASS (in no .sc of the pack and not in SuperCollider's class library): $missing"; else say "$name: every UGen has a class"; fi
    if [ -n "$dup" ]; then say "$name: ERROR: class names defined twice (comments not counted): $dup"; else say "$name: no class name is defined twice"; fi
    rev=$(git -C "$revsrc" rev-parse HEAD 2> /dev/null | cut -c1-12)
    git -C "$revsrc" rev-parse HEAD > "$dest/SOURCE-REVISION.txt" 2> /dev/null
    if [ "$scx" -gt 0 ] && [ "$classes" -gt 0 ] && [ -n "$rev" ] && [ -z "$dup" ]; then
        echo "${rev}-L${PACK_LAYOUT}" > "$dest/PACK-ID.txt"
        say "$name: PACK-ID $(cat "$dest/PACK-ID.txt")"
    else
        say "$name: NO PACK-ID (needs plug-in files AND class files AND no duplicate class): the pack is NOT put into the zip"
    fi
}

# --- end pack checks

# ---- sc3-plugins: the class files of every directory that has them are copied beside the .scx files
SC3P_SRC="$WORK/sc3-plugins"
if clone https://github.com/supercollider/sc3-plugins.git "$SC3P_TAG" "$SC3P_SRC" > "$OUT/logs/clone-sc3p.log" 2>&1; then
    git -C "$SC3P_SRC" describe --tags --always 2>/dev/null | tee -a "$REPORT"
    build_pack sc3-plugins "$SC3P_SRC" -DQUARKS=OFF
    dest="$OUT/seed/sc3-plugins"
    # class files, per source directory: every .sc file ONCE, with its path below the directory (copying "sc" and "sc/classes" as folders defined every class twice: sclang stopped at "duplicate Class found").
    # a directory whose plug-in did not build keeps its classes out (they would call UGens that are not there)
    for top_dir in "$SC3P_SRC"/source/*/; do
        top=$(basename "$top_dir")
        if grep -q "source/$top/" "$OUT/logs/failed-sc3-plugins.txt" 2> /dev/null; then
            say "classes of $top left out (its plug-in did not build)"
            continue
        fi
        (
            cd "$top_dir" || exit 0
            find . -name '*.sc' -not -ipath '*HelpSource*' -not -ipath '*/help/*' -not -ipath '*/test*' | while read -r f; do
                mkdir -p "$dest/classes/$top/$(dirname "$f")" && cp "$f" "$dest/classes/$top/$f"
            done
        )
    done
    cp "$SC3P_SRC"/COPYING* "$SC3P_SRC"/LICENSE* "$SC3P_SRC"/README* "$dest/" 2> /dev/null || true
    find "$SC3P_SRC/source" -maxdepth 2 \( -iname 'COPYING*' -o -iname 'LICENSE*' \) -exec sh -c 'for f; do mkdir -p "$0/licences/$(basename "$(dirname "$f")")" && cp "$f" "$0/licences/$(basename "$(dirname "$f")")/"; done' "$dest" {} +
    finish_pack sc3-plugins "$SC3P_SRC/source" "$SC3P_SRC"
else
    say "FAIL: could not clone sc3-plugins"
fi

# ---- mi-UGens (the class files are in sc/Classes of the repository, the sources of the plug-ins in projects/)
MI_SRC="$WORK/mi-UGens"
if clone https://github.com/v7b1/mi-UGens.git "$MIUGENS_REF" "$MI_SRC" > "$OUT/logs/clone-mi.log" 2>&1; then
    # MiBraids links a libsamplerate that its source tree expects pre-built in projects/MiBraids/libsamplerate/build (Release, as a Visual Studio build puts it)
    if [ -f "$MI_SRC/projects/MiBraids/libsamplerate/CMakeLists.txt" ]; then
        say "== mi-UGens: libsamplerate for MiBraids"
        ( cmake -S "$MI_SRC/projects/MiBraids/libsamplerate" -B "$MI_SRC/projects/MiBraids/libsamplerate/build" -G "Visual Studio 17 2022" -A x64 \
            -DBUILD_TESTING=OFF -DLIBSAMPLERATE_EXAMPLES=OFF -DBUILD_SHARED_LIBS=OFF \
          && cmake --build "$MI_SRC/projects/MiBraids/libsamplerate/build" --config Release ) > "$OUT/logs/libsamplerate.log" 2>&1 \
            || { say "libsamplerate FAILED (logs/libsamplerate.log): the errors:"; grep -m 8 -E "error|Error" "$OUT/logs/libsamplerate.log" | tee -a "$REPORT"; }
    else
        say "mi-UGens: no libsamplerate sources in projects/MiBraids (submodule missing?)"
    fi
    build_pack mi-UGens "$MI_SRC"
    dest="$OUT/seed/mi-UGens"
    # the class files: sc/Classes (an earlier version looked for Classes at the top of the repository, which does not exist: the pack had plug-in files and no classes)
    if [ -d "$MI_SRC/sc/Classes" ]; then
        mkdir -p "$dest/Classes" && cp "$MI_SRC"/sc/Classes/*.sc "$dest/Classes/"
    else
        say "mi-UGens: ERROR: no sc/Classes folder in the repository: the pack would have no classes"
    fi
    # licences: GPL-3.0 text, the MIT licence of the Mutable Instruments code (eurorack/LICENSE.txt) and the readme
    [ -f "$MI_SRC/gpl-3.0.md" ] && cp "$MI_SRC/gpl-3.0.md" "$dest/LICENSE-GPL-3.0.md"
    [ -f "$MI_SRC/eurorack/LICENSE.txt" ] && cp "$MI_SRC/eurorack/LICENSE.txt" "$dest/LICENSE-eurorack-mutable-instruments.txt"
    cp "$MI_SRC"/README* "$dest/" 2> /dev/null || true
    # where the pack goes: the per-user extensions folder of a real norns (the emplaitress mod looks for MiPlaits.sc there and, when it is not there, downloads and unpacks a Linux copy: two copies of every class)
    echo user > "$dest/PACK-TARGET.txt"
    finish_pack mi-UGens "$MI_SRC/projects" "$MI_SRC"
else
    say "FAIL: could not clone mi-UGens"
fi

# ---- NamAmp: only with a source URL
if [ -n "${NAMAMP_URL:-}" ]; then
    NA_SRC="$WORK/namamp"
    if clone "$NAMAMP_URL" "${NAMAMP_REF:-HEAD}" "$NA_SRC" > "$OUT/logs/clone-namamp.log" 2>&1; then
        build_pack NamAmp "$NA_SRC"
        finish_pack NamAmp "$NA_SRC" "$NA_SRC"
    else
        say "FAIL: could not clone NamAmp ($NAMAMP_URL)"
    fi
else
    say "NamAmp: NOT BUILT: no source URL was given (the owner has to name the repository that defines the NamAmp UGen)"
fi

if ! find "$OUT/seed" -name "*.scx" 2> /dev/null | grep -q .; then echo "::warning::no plug-in pack was built: see m7-report.txt"; fi
# the size, as the zip will see it
say "== sizes"
for p in "$OUT"/seed/*; do [ -d "$p" ] && say "$(basename "$p"): $(du -sk "$p" | cut -f1) KiB unpacked"; done
( cd "$OUT/seed" && 7z a -tzip -mx=9 "$OUT/seed-test.zip" . > /dev/null 2>&1 && say "all packs zipped: $(du -k "$OUT/seed-test.zip" | cut -f1) KiB" )
rm -f "$OUT/seed-test.zip"
exit 0
