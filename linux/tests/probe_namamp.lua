-- the real princeton script on a norns that starts with the Raspberry Pi NamAmp.so in the extension folder (linux/tests/namamp_boot_test.sh):
-- the launcher moved it aside and seeded Verdandi's x86-64 copy before sclang started; the script's own install step must see NAM as installed and leave the copy alone;
-- the engine plays a NAM model (signal); a wrong-architecture plug-in that a script installs while norns runs gets a note and a CLEAN UP line, moved only after the confirmation
#sleep 4
print("PROBE start note", tostring(_menu.heal_note))
print("PROBE start runtime note", tostring(_menu.mi_note))
print("PROBE engines", table.concat(engine.names or {}, ","))
#sh sha256sum "$NORNS_HOME/.local/share/SuperCollider/Extensions/princeton/NamAmp.so" | cut -d' ' -f1 > "$MARKS.ext_before"; sha256sum "$NORNS_HOME/dust/code/princeton/lib/nam/NamAmp.so" | cut -d' ' -f1 > "$MARKS.script_before"
#sh /tmp/nam/tone 110 0.1 > /dev/null 2>&1 &
#sleep 1
norns.script.load("/home/we/dust/code/princeton/princeton.lua")
#sleep 14
nam = include("lib/nam")
print("PROBE nam status", nam.install())
nam.scan()
print("PROBE nam files", #nam.files, tostring(nam.available()))
#sh sha256sum "$NORNS_HOME/.local/share/SuperCollider/Extensions/princeton/NamAmp.so" | cut -d' ' -f1 > "$MARKS.ext_after"; sha256sum "$NORNS_HOME/dust/code/princeton/lib/nam/NamAmp.so" | cut -d' ' -f1 > "$MARKS.script_after"
#sh for p in $(jack_lsp | grep -i 'crone.*in' ); do jack_connect nam_tone:out "$p" 2>/dev/null; done
#sleep 2
#sh /tmp/nam/jack_peak 2 $(jack_lsp | grep -i 'crone.*out' | head -2) > "$MARKS.peak_off" 2>&1
engine.nam_load(nam.dir .. nam.files[#nam.files])
#sleep 3
engine.nam_on(1)
#sleep 3
#sh /tmp/nam/jack_peak 2 $(jack_lsp | grep -i 'crone.*out' | head -2) > "$MARKS.peak_on" 2>&1
engine.nam_on(0)
print("PROBE nam played")
#sh mkdir -p "$NORNS_HOME/.local/share/SuperCollider/Extensions/late-pack" && printf '\177ELF\001\001\001\000\000\000\000\000\000\000\000\000\003\000\050\000\000\000' > "$NORNS_HOME/.local/share/SuperCollider/Extensions/late-pack/Late_scsynth.so"
#sleep 9
print("PROBE runtime note", tostring(_menu.mi_note))
print("PROBE runtime fix", tostring(_norns.mi_foreign_fix_text()):gsub("\n", " | "))
_menu.set_page("CLEANUP")
page = _menu.m["CLEANUP"]
found = false
for i = 1, #page.rows do if page.rows[i].name == "PROBLEM" and page.rows[i].problem.target:find("late-pack", 1, true) then page.pos = i; found = true end end
print("PROBE cleanup row", tostring(found))
page.key(3, 1)
print("PROBE not moved before the confirmation", tostring(io.open(os.getenv("NORNS_HOME") .. "/.local/share/SuperCollider/Extensions/late-pack/Late_scsynth.so") ~= nil))
page.key(3, 1)
print("PROBE moved after the confirmation", tostring(io.open(os.getenv("NORNS_HOME") .. "/.local/share/SuperCollider/Extensions/late-pack/Late_scsynth.so") == nil))
#sleep 5
print("PROBE runtime note after", tostring(_menu.mi_note))
#sh pkill -x nam_tone
print("PROBE namamp done")
