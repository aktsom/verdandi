// Verdandi (Windows build): the start-up check of the plug-in packs. every pack that Verdandi seeds into <home>/extensions carries UNITS.txt, the UGen names its plug-in files define (written by the build
// from the sources). after the class library is compiled every one of them has to be a class sclang knows: an engine that calls a UGen without its class stops with "Class 'X' not found" (and, before
// VerdandiSafeInit.sc, took the whole start-up down). ONE plain line in the log names what is missing; the full list is in <home>/logs/pack-check.txt. nothing is changed.
VerdandiPackCheck {
	*initClass {
		StartUp.add { this.run };
	}

	*run {
		var home, ext, missing, packs, line, shown, report, path, f;
		home = "NORNS_HOME".getenv;
		if(home.isNil or: { home.isEmpty }) { ^this };
		ext = home +/+ "extensions";
		if(File.exists(ext).not and: { PathName(ext).isFolder.not }) { ^this };
		missing = List.new;
		packs = Set.new;
		try {
			PathName(ext).folders.do { |pack|
				var units = pack.fullPath +/+ "UNITS.txt";
				if(File.exists(units)) {
					File.readAllString(units).split($\n).do { |name|
						name = name.stripWhiteSpace;
						if(name.size > 0 and: { name.asSymbol.asClass.isNil }) {
							missing.add(name ++ " (" ++ pack.folderName ++ ")");
							packs.add(pack.folderName);
						};
					};
				};
			};
		} { |err|
			("### plug-in pack check could not run: " ++ err.errorString).postln;
			^this
		};
		if(missing.size == 0) {
			"plug-in packs: every UGen of the packs has its class".postln;
			^this
		};
		shown = missing.keep(12).join(", ");
		line = "### plug-in packs: " ++ missing.size ++ " UGens have no class in sclang: " ++ shown
			++ (missing.size > 12).if { ", and " ++ (missing.size - 12) ++ " more" } { "" }
			++ ". a script whose engine uses one of them stops with Class 'X' not found (packs: " ++ packs.asArray.sort.join(", ") ++ "; full list: logs/pack-check.txt)";
		line.postln;
		path = home +/+ "logs" +/+ "pack-check.txt";
		try {
			f = File(path, "w");
			f.write(missing.join("\n") ++ "\n");
			f.close;
		};
	}
}
