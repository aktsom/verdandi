-- the light script of the measurement (res.txt): PolyPerc plays a pattern at 4 notes a second (clock.sync(1/2) at 120 bpm), one softcut voice loops a 4 s buffer
engine.name = "PolyPerc"
local music = require "musicutil"
function init()
  softcut.buffer_clear()
  softcut.enable(1, 1); softcut.buffer(1, 1); softcut.level(1, 0.5); softcut.rate(1, 1); softcut.loop(1, 1)
  softcut.loop_start(1, 0); softcut.loop_end(1, 4); softcut.position(1, 0); softcut.play(1, 1); softcut.rec(1, 1)
  softcut.level_input_cut(1, 1, 1.0); softcut.rec_level(1, 1.0); softcut.pre_level(1, 0.5)
  local scale = music.generate_scale(48, "minor pentatonic", 3)
  local i = 0
  clock.run(function() while true do clock.sync(1/2); i = i + 1; engine.hz(music.note_num_to_freq(scale[(i * 3) % #scale + 1])) end end)
end
