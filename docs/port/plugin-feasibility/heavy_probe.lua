-- a heavier script for the measurement: PolySub (an expensive synth) with many overlapping notes, all six softcut voices looping
engine.name = "PolySub"
local music = require "musicutil"
function init()
  softcut.buffer_clear()
  for v = 1, 6 do
    softcut.enable(v, 1); softcut.buffer(v, v % 2 + 1); softcut.level(v, 0.3); softcut.rate(v, 1 + v * 0.01); softcut.loop(v, 1)
    softcut.loop_start(v, 0); softcut.loop_end(v, 2 + v); softcut.position(v, 0); softcut.play(v, 1); softcut.rec(v, 1)
    softcut.level_input_cut(1, v, 1.0); softcut.rec_level(v, 1.0); softcut.pre_level(v, 0.7)
  end
  params:set("release", 4)
  local scale = music.generate_scale(36, "minor pentatonic", 4)
  local i = 0
  clock.run(function() while true do clock.sync(1/4); i = i + 1; engine.start(i % 8, music.note_num_to_freq(scale[(i * 3) % #scale + 1])) end end)
end
