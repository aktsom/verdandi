-- the self-healing for the Raspberry Pi mi-UGens in a headless boot (linux/tests/mi_heal_boot_test.sh): the launcher moved a download aside before sclang started
-- (the note was left for the menu and shows once), and a download while norns runs is noticed (a note, the CLEAN UP line, moved after the confirmation)
home = os.getenv("NORNS_HOME")
function exists(p) local f = io.open(p) if f then f:close() return true end return false end
E = home .. "/.local/share/SuperCollider/Extensions"
#sleep 3
print("PROBE start note", tostring(_menu.heal_note))
print("PROBE start note file gone", tostring(not exists(home .. "/.mi-heal-note")))
print("PROBE start moved", tostring(not exists(E .. "/arm-pack") and exists(E .. "/mi-UGens/Classes/MiPlaits.sc")))
print("PROBE start runtime note", tostring(_menu.mi_note))
#sh mkdir -p "$NORNS_HOME/.local/share/SuperCollider/Extensions/late-pack/Classes" && printf '\177ELF\001\001\001\000\000\000\000\000\000\000\000\000\003\000\050\000\000\000' > "$NORNS_HOME/.local/share/SuperCollider/Extensions/late-pack/MiRings.so" && echo "// theirs" > "$NORNS_HOME/.local/share/SuperCollider/Extensions/late-pack/Classes/MiRings.sc"
#sleep 9
print("PROBE runtime note", tostring(_menu.mi_note))
print("PROBE runtime fix", tostring(_norns.mi_foreign_fix_text()):gsub("\n", " | "))
print("PROBE runtime still there", tostring(exists(E .. "/late-pack/MiRings.so")))
_menu.set_page("CLEANUP")
page = _menu.m["CLEANUP"]
found = false
for i = 1, #page.rows do if page.rows[i].name == "PROBLEM" and page.rows[i].problem.target:find("late-pack", 1, true) then page.pos = i; found = true end end
print("PROBE cleanup row", tostring(found))
page.key(3, 1)
print("PROBE not moved before the confirmation", tostring(exists(E .. "/late-pack/MiRings.so")))
page.key(3, 1)
print("PROBE moved after the confirmation", tostring(not exists(E .. "/late-pack/MiRings.so")))
#sleep 6
print("PROBE runtime note after", tostring(_menu.mi_note))
print("PROBE heal done")
