-- a script with parameters, for the preview of the PARAMS menu page (docs/port/ui-previews/make_previews.sh)
engine.name = "PolyPerc"

function init()
  params:add_separator("PREVIEW")
  params:add{type = "control", id = "cutoff", name = "cutoff",
    controlspec = controlspec.new(50, 5000, "exp", 0, 800, "hz")}
  params:add{type = "control", id = "release", name = "release",
    controlspec = controlspec.new(0.1, 3.2, "lin", 0, 1.2, "s")}
  params:add{type = "number", id = "octave", name = "octave", min = -2, max = 2, default = 0}
  params:add{type = "option", id = "scale", name = "scale", options = {"major", "minor", "dorian"}, default = 1}
  params:add{type = "taper", id = "amp", name = "amp", min = 0, max = 1, default = 0.5, k = 2}
  params:add{type = "binary", id = "run", name = "run", behavior = "toggle", default = 1}
end

function redraw() screen.clear(); screen.update() end
