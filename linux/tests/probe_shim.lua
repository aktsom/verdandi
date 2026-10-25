-- a script runs the Raspberry Pi's restart command with os.execute (as a script's installer does): on this build it must return at once, without sudo or a
-- password, and norns must restart itself through linux/norns.sh (linux/shims, lua/core/menu.lua). the sidecar sees the same shims on its PATH.
norns.system_cmd("command -v sudo; command -v systemctl; echo _done_", function(out) print("PROBE sidecar which", (out or ""):gsub("\n", " ")) end)
#sleep 2
t0 = util.time()
r = os.execute("sudo systemctl restart norns-jack.service norns-crone.service norns-matron.service")
print("PROBE execute returned", r, string.format("%.1f", util.time() - t0) .. " s")
#sleep 45
#sh jack_lsp | grep -c '^crone:' > "$MARKS.crone"
print("PROBE after the restart")
