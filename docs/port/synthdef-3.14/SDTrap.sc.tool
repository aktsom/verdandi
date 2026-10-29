+ SynthDef {
	build { arg ugenGraphFunc, rates, prependArgs;
		var ok = true;
		try {
			this.initBuild;
			this.buildUgenGraph(ugenGraphFunc, rates, prependArgs);
			this.finishBuild;
			func = ugenGraphFunc;
		} { |e| ok = false; UGen.buildSynthDef = nil; ("SDFAIL " ++ name ++ " :: " ++ e.errorString.replace("\n", " ")).postln };
		if(ok) { ("SDOK " ++ name).postln };
	}
}
