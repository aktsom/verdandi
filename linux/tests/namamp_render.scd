// linux/tests/namamp_render_test.sh: renders 4 seconds offline with scsynth (non-real-time): a sine of freq at amp 0.1 starts at 0.5 s through NamAmp.ar(in, act) after the plug-in
// command /cmd namLoad <model> <gain>. args: model, output wav, act (0|1), freq, plug-in folder, scsynth plug-in folder, scsynth, gain
var model = thisProcess.argv[0], out = thisProcess.argv[1], active = thisProcess.argv[2].asInteger, freq = thisProcess.argv[3].asFloat;
var plugs = thisProcess.argv[4], scplugs = thisProcess.argv[5], scsynth = thisProcess.argv[6], gain = thisProcess.argv[7].asFloat;
var def, score, opts;
def = SynthDef(\namtest, { |amp = 0.1, act = 1|
    var in = SinOsc.ar(freq) * amp;
    Out.ar(0, NamAmp.ar(in, act));
});
score = Score([
    [0.0, [\d_recv, def.asBytes]],
    [0.0, [\cmd, \namLoad, model, gain]],
    [0.5, [\s_new, \namtest, 1000, 0, 0, \act, active]],
    [3.5, [\c_set, 0, 0]]
]);
opts = ServerOptions.new;
opts.numOutputBusChannels = 1; opts.numInputBusChannels = 0;
opts.sampleRate = 48000;
opts.memSize = 65536 * 4;
Score.program = scsynth;
opts.ugenPluginsPath = scplugs ++ ":" ++ plugs;
score.recordNRT(out ++ ".osc", out, nil, 48000, "WAV", "float", opts, "", 4.0, { 0.exit });
