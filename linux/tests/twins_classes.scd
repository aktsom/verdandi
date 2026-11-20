// linux/twins_check.py: which of the class names (the arguments) does this sclang know? prints "CLASS <name> true|false" and exits. HOME is a norns home with the shipped pack in its extension folder.
thisProcess.argv.do { |n| ("CLASS " ++ n ++ " " ++ n.asSymbol.asClass.notNil).postln };
"CLASSES DONE".postln;
0.exit;
