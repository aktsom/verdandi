# sourced by the build scripts (docs/port/phase-m35.md): what to say when a tool the build needs is missing.
# the one place that installs them all is linux/setup-deps.sh; this prints the exact command for the tools that are missing here.

# the apt package that holds a tool (Ubuntu / Linux Mint)
tool_package() {
    case "$1" in
        c++ | g++ | gcc | cc | make | strip) echo build-essential ;;
        ninja) echo ninja-build ;;
        cmake) echo cmake ;;
        git) echo git ;;
        curl) echo curl ;;
        python3) echo python3 ;;
        pkg-config) echo pkg-config ;;
        go) echo golang-go ;;
        xz) echo xz-utils ;;
        tar) echo tar ;;
        sha256sum) echo coreutils ;;
        node | npm) echo nodejs npm ;;
        *) echo "$1" ;;
    esac
}

# missing_tools_list <tool>...: the tools that are not found, one per line
missing_tools_list() {
    local t
    for t in "$@"; do command -v "$t" > /dev/null 2>&1 || echo "$t"; done
}

# missing_tools_warning <what the build makes> <tool>...: prints a warning with the exact install command and returns 1 when a tool is missing; 0 when all are there
missing_tools_warning() {
    local what="$1" miss pk="" t p
    shift
    miss="$(missing_tools_list "$@" | tr '\n' ' ')"
    [ -n "$miss" ] || return 0
    for t in $miss; do
        for p in $(tool_package "$t"); do
            case " $pk " in *" $p "*) ;; *) pk="$pk $p" ;; esac
        done
    done
    echo "WARNING: $what was not built, because these tools are not installed:$(printf ' %s' $miss)"
    echo "         install them with:  sudo apt install${pk}"
    echo "         (or run linux/setup-deps.sh, which installs everything the build needs), then run linux/build.sh again. Verdandi starts without this part."
    return 1
}
