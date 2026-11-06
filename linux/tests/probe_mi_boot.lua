-- linux/tests/mi_boot_test.sh: the Emplaitress mod is enabled and the shipped mi-UGens pack was seeded before sclang started
#sleep 6
print("PROBE engines", tostring(engine and engine.names and #engine.names))
local names = {} for _, n in ipairs(engine.names or {}) do names[#names + 1] = n end
print("PROBE names", table.concat(names, ","))
print("PROBE boot done")
