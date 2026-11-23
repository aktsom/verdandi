// linux/tests/mi_checkout_test.sh: sclang started with HOME = a norns home: the classes of the mi-UGens are found (class library), and a synth that uses MiPlaits and MiRings
// (what the mods emplaitress and fx_resonator do) is rendered offline by the real scsynth (non-real-time), which has to load the plug-ins. prints "CLASS <name> true|false", "RENDERED" and exits.
// without the classes the mods stop with "Message 'ar' not understood" (receiver nil): the control run shows that this is what a missing pack looks like.
// args: output wav, then the class names
var out = thisProcess.argv[0], names = thisProcess.argv[1..], all = true, def, score, opts;
names.do { |n| var there = n.asSymbol.asClass.notNil; ("CLASS " ++ n ++ " " ++ there).postln; all = all and: there };
if(all) {
    def = SynthDef(\mitest, {
        var plaits = \MiPlaits.asClass.ar(60, 0, 0.3, 0.5, 0.5, 1);
        var rings = \MiRings.asClass.ar(plaits, 0, 0, 0.5, 0.5);
        Out.ar(0, rings.asArray.first);
    });
    score = Score([
        [0.0, [\d_recv, def.asBytes]],
        [0.0, [\s_new, \mitest, 1000, 0, 0]],
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
