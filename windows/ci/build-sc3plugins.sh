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

# ---- sc3-plugins: the class files of every directory that has them are copied beside the .scx files
SC3P_SRC="$WORK/sc3-plugins"
if clone https://github.com/supercollider/sc3-plugins.git "$SC3P_TAG" "$SC3P_SRC" > "$OUT/logs/clone-sc3p.log" 2>&1; then
    git -C "$SC3P_SRC" describe --tags --always 2>/dev/null | tee -a "$REPORT"
    build_pack sc3-plugins "$SC3P_SRC" -DQUARKS=OFF
    dest="$OUT/seed/sc3-plugins"
    # class files and the licences, per source directory; a directory whose targets all failed keeps its classes out (they would call UGens that are not there)
    find "$SC3P_SRC/source" -type d \( -name Classes -o -name classes -o -name sc \) 2> /dev/null | while read -r d; do
        rel="${d#"$SC3P_SRC"/source/}"
        top="${rel%%/*}"
        if grep -q "source/$top/" "$OUT/logs/failed-sc3-plugins.txt" 2> /dev/null && ! find "$WORK/build-sc3-plugins" -path "*$top*" -name '*.scx' 2> /dev/null | grep -q .; then
            say "classes of $top left out (its plug-in did not build)"
            continue
        fi
        mkdir -p "$dest/classes/$top" && cp -r "$d"/. "$dest/classes/$top/"
    done
    cp "$SC3P_SRC"/COPYING* "$SC3P_SRC"/LICENSE* "$SC3P_SRC"/README* "$dest/" 2> /dev/null || true
    find "$SC3P_SRC/source" -maxdepth 2 \( -iname 'COPYING*' -o -iname 'LICENSE*' \) -exec sh -c 'for f; do mkdir -p "$0/licences/$(basename "$(dirname "$f")")" && cp "$f" "$0/licences/$(basename "$(dirname "$f")")/"; done' "$dest" {} +
    git -C "$SC3P_SRC" rev-parse HEAD > "$dest/SOURCE-REVISION.txt" 2> /dev/null
else
    say "FAIL: could not clone sc3-plugins"
fi

# ---- mi-UGens
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
    [ -d "$MI_SRC/Classes" ] && mkdir -p "$dest/Classes" && cp -r "$MI_SRC/Classes"/. "$dest/Classes/"
    cp "$MI_SRC"/LICENSE* "$MI_SRC"/README* "$dest/" 2> /dev/null || true
    git -C "$MI_SRC" rev-parse HEAD > "$dest/SOURCE-REVISION.txt" 2> /dev/null
else
    say "FAIL: could not clone mi-UGens"
fi

# ---- NamAmp: only with a source URL
if [ -n "${NAMAMP_URL:-}" ]; then
    NA_SRC="$WORK/namamp"
    if clone "$NAMAMP_URL" "${NAMAMP_REF:-HEAD}" "$NA_SRC" > "$OUT/logs/clone-namamp.log" 2>&1; then
        build_pack NamAmp "$NA_SRC"
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
