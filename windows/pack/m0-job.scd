// M0b, run on your own PC by verdandi-test.cmd: compile check + a score for scsynth's offline render. same as windows/ci/smoke-sc.sh does on the runner.
(
var def, score, out = "score.osc"; // relative: the program runs in this folder
"M0B-CLASSLIB-OK".postln;
("M0B-NOBOOT: " ++ Crone.bootOnInit).postln;
("M0B-NORNS-CLASSES: " ++ [\Crone, \CroneEngine, \CronePoll].collect { |c| c.asClass.notNil }).postln;
def = SynthDef(\m0sine, { |out = 0, freq = 440| Out.ar(out, SinOsc.ar(freq, 0, 0.3) ! 2) });
score = [
    [0.0, ['/d_recv', def.asBytes]],
    [0.0, ['/s_new', \m0sine, 1000, 0, 0]],
    [1.0, ['/c_set', 0, 0]]
];
Score.write(score, out);
"M0B-SCORE-WRITTEN".postln;
0.exit;
)
