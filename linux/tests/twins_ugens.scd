// linux/tests/portedplugins_boot_test.sh: sclang started with HOME = a norns home: every class twins asks for is found (class library), and a synth that uses the three PortedPlugins UGens
// the way twins' engine does is rendered offline by the real scsynth (non-real-time), which has to load the plug-ins. prints "CLASS <name> true|false", "RENDERED" and exits.
// args: output wav, then the class names
var out = thisProcess.argv[0], names = thisProcess.argv[1..], all = true, def, score, opts;
names.do { |n| var there = n.asSymbol.asClass.notNil; ("CLASS " ++ n ++ " " ++ there).postln; all = all and: there };
if(all and: { names.indexOfEqual("AnalogChew").notNil }) {
    def = SynthDef(\twtest, {
        var in = SinOsc.ar(220) * 0.2;
        // (the classes by name: a file that names a class which does not exist does not compile, and the control run, without the pack, must get to its "NOT RENDERED")
        var chew = \AnalogChew.asClass.ar(in, 0.5, 0.5, 0.5);
        var degrade = \AnalogDegrade.asClass.ar(\AnalogLoss.asClass.ar(chew, 0.5, 1, 0.5, 0.5), 0.4, 0.5, 0.5, 0.5);
        Out.ar(0, degrade);
    });
    score = Score([
        [0.0, [\d_recv, def.asBytes]],
        [0.0, [\s_new, \twtest, 1000, 0, 0]],
        [1.0, [\c_set, 0, 0]]
    ]);
    opts = ServerOptions.new;
    opts.numOutputBusChannels = 1; opts.numInputBusChannels = 0;
    opts.sampleRate = 48000;
    score.recordNRT(out ++ ".osc", out, nil, 48000, "WAV", "float", opts, "", 1.0, { "RENDERED".postln; 0.exit });
} {
    "NOT RENDERED".postln;
    0.exit;
};
