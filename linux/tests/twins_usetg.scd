// linux/tests/twins_boot_test.sh: the condition under which the engine of twins takes TwinGrain (engine_twins.sc, `useTG`), asked of a real sclang that started with the home of the boot test: the class is known and its plug-in file is beside its class file
var c = \TwinGrain.asClass;
var d = if(c.notNil, { PathName(c.filenameSymbol.asString).pathOnly }, { "" });
("USETG " ++ (c.notNil and: { File.exists(d ++ "TwinGrain.so") or: { File.exists(d ++ "TwinGrain_scsynth.so") } })).postln;
0.exit;
