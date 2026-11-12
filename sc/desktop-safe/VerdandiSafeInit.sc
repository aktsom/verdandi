// Verdandi (desktop builds): one extension whose initClass fails must not stop sclang's start-up. The stock Class.initClassTree lets the error
// leave Process.startup, so the rest of the class tree is never initialised, the StartUp callbacks never run and no server boots. Here a failing
// initClass is reported (one line in the log, naming the class) and the tree goes on. Same code as the stock method otherwise.
+ Class {
	*initClassTree { arg aClass;
		if(classesInited.isNil, { classesInited = IdentitySet.new });
		if(classesInited.includes(aClass).not, {
			classesInited.add(aClass);

			if(aClass.isMetaClass.not and: { aClass.class.findMethod(\initClass).notNil }, {
				try {
					aClass.initClass;
				} { |err|
					("### initClass of " ++ aClass.name ++ " failed, start-up goes on: " ++ err.errorString).postln;
				};
			});

			if(aClass.subclasses.notNil, {
				aClass.subclasses.do({ arg class; this.initClassTree(class); });
			});
		});
	}
}
