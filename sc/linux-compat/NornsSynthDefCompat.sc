// SuperCollider 3.14 refuses Clip.ar (InRange.ar) with a control-rate or constant first input ("Clip first input is not audio rate"); 3.13 let it through and the audio-rate
// Clip read past the end of the one-sample input. Some mods still do that (mx_malone of nb_mxsynths, docs/port/KNOWN-ISSUES.md item 21), and the error stops the mod from creating
// its other voices. while a SynthDef whose NAME is on the list below is being built, Clip.ar turns such an input into K2A.ar (which is what the author meant); every other SynthDef is
// checked as before. no file of the user's is touched. loaded only by the Linux launcher (the folder is in sclang_conf.yaml; NORNS_SC_COMPAT=0 leaves it out).
// the list is data: more names with NORNS_SYNTHDEF_COMPAT="name1,name2" in the environment of the launcher. a general fix for every def (Clip.ar everywhere) is NOT installed:
// docs/port/synthdef-3.14/ClipKr.sc.proposal.

NornsSynthDefCompat {
	classvar <names, <reported;

	*initClass {
		names = Set[\mx_malone];
		"NORNS_SYNTHDEF_COMPAT".getenv.notNil.if {
			"NORNS_SYNTHDEF_COMPAT".getenv.split($,).do { |n| n = n.stripWhiteSpace; if(n.size > 0) { names.add(n.asSymbol) } }
		};
		reported = Set.new;
	}

	// the SynthDef that is being built right now is on the list
	*applies {
		var sd = UGen.buildSynthDef;
		^sd.notNil and: { names.includes(sd.name.asSymbol) }
	}

	// an input that is not audio rate becomes audio rate (arrays: each channel)
	*audioInput { |in|
		var changed = false;
		var out = in.asArray.collect { |x|
			if(x.rate != \audio) { changed = true; K2A.ar(x) } { x }
		};
		if(changed and: { reported.includes(UGen.buildSynthDef.name.asSymbol).not }) {
			reported.add(UGen.buildSynthDef.name.asSymbol);
			("NornsSynthDefCompat:" + UGen.buildSynthDef.name + ": Clip.ar got a control-rate input, built with K2A.ar (SuperCollider 3.14 refuses it)").postln;
		};
		^out.unbubble
	}
}

+ Clip {
	*ar { |in, lo = 0.0, hi = 1.0|
		if(NornsSynthDefCompat.applies) { in = NornsSynthDefCompat.audioInput(in) };
		^this.multiNew('audio', in, lo, hi)
	}
}
