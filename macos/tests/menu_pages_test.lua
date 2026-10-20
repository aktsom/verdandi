-- scenarios for the E1 menu pages in lua/core/menu.lua. run from the repo root:
--   <lua 5.3> macos/tests/menu_pages_test.lua
-- pulls next_panel out of lua/core/menu.lua and runs it against both platforms
local src = io.open("lua/core/menu.lua"):read("a")
local fn = src:match("(local wrap_panels.-\nend\n)")
assert(fn, "next_panel not found")
util = {clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end}
local fails = 0
local function run(platform, cases)
  local getenv = os.getenv
  os.getenv = function(k) if k == "NORNS_PLATFORM" then return platform end return getenv(k) end
  _menu = {panels = {"MIX", "TAPE", "HOME", "PARAMS"}}
  local next_panel = load(fn .. "\nreturn next_panel")()
  os.getenv = getenv
  for _, c in ipairs(cases) do
    _menu.panel = c[1]
    local got = next_panel(c[2])
    if got ~= c[3] then fails = fails + 1; print("FAIL", platform, c[1], c[2], got, "want", c[3]) end
  end
end
-- computer: round
run("macos", {{4, 1, 1}, {1, -1, 4}, {3, 1, 4}, {2, -1, 1}, {4, 2, 2}, {1, -5, 4}})
-- device: stops at the ends
run(nil, {{4, 1, 4}, {1, -1, 1}, {3, 1, 4}, {2, -1, 1}})
print(fails == 0 and "menu pages: all scenarios pass" or (fails .. " failures"))
os.exit(fails == 0)
