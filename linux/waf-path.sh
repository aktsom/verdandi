# sourced by linux/setup-deps.sh, linux/build.sh and linux/tests/run_all.sh: where waf lives.
# waf unpacks its library next to itself on first use, so the folder must belong to the user who builds:
# the default is ~/.local/share/waf (of the user who ran setup-deps.sh, also with sudo), not /opt.
# WAF_DIR overrides where setup-deps.sh installs it; WAF (build/test) names the waf to use.

waf_user_home() {
    if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" -eq 0 ]; then
        getent passwd "$SUDO_USER" | cut -d: -f6
    else
        echo "$HOME"
    fi
}
if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" -eq 0 ]; then
    WAF_DEFAULT_DIR="$(waf_user_home)/.local/share/waf"
else
    WAF_DEFAULT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/waf"
fi

# the waf to run: $WAF, the user's, an older install in /opt/waf (readable, but waf cannot unpack there
# unless it is writable), else one on the PATH
find_waf() {
    local c
    for c in "${WAF:-}" "$WAF_DEFAULT_DIR/waf" "$HOME/.local/share/waf/waf" /opt/waf/waf; do
        [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return; }
    done
    command -v waf || true
}
