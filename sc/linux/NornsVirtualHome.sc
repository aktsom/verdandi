// the virtual /home/we for SuperCollider on the Linux desktop (docs/port/KNOWN-ISSUES.md item 20, linux/tests/sc_virtual_home_test.sh).
//
// on a real norns HOME is /home/we, and scripts and engines write that path into their code ("/home/we/dust/code/dronecaster/engine/drones"). here the norns home is an
// ordinary folder (the real HOME, for example ~/Verdandi) and /home/we is only a name: lua translates it where paths leave lua (core/virtual_home.lua), but SuperCollider
// opens what its code says. this file makes sclang translate it too, in the places where a path reaches the file system or scsynth:
//   String   standardizePath, realPath, pathMatch (so PathName, glob, SoundFile.collect), systemCmd, unixCmd, unixCmdGetStdOut (a command line that names a path)
//   File     exists, delete, deleteAll, mtime, realpath, mkdir, copy, type, fileSize, open (so File.use, readAllString, executeFile, "path".load, SynthDef.writeDefFile ...)
//   SoundFile  openRead, openWrite
//   Server   sendMsg, sendBundle, listSendMsg, listSendBundle, sendMsgSync (what scsynth opens: Buffer.read, /b_allocRead, /b_write, /d_load, /d_loadDir ...)
// only the path component "/home/we" is translated (as in lua): "/home/weird" and "/tmp/home/we" are left alone. nothing happens when HOME already is /home/we (a real norns),
// and this folder is on sclang's include path only in the Linux launcher's sclang_conf.yaml, so the device and the Mac never load it.
// not covered: a path that is built inside scsynth or a plug-in, a program started by an engine that reads /home/we itself (shell commands named through systemCmd/unixCmd
// are translated, other programs started some other way are not), and strings sent to matron (they stay virtual, which is what lua expects).

NornsVirtualHome {
	classvar <virtual = "/home/we", <real;

	*initClass {
		var h = "HOME".getenv;
		real = if(h.notNil and: { h.size > 1 and: { h != virtual and: { h[0] == $/ } } }) { h } { nil };
	}

	*isNameChar { |c| ^c.isAlphaNum or: { c == $_ or: { c == $. or: { c == $- } } } }

	// the string with every whole path component "/home/we" replaced by the real home
	*mapped { |p|
		var out, from = 0, i, n = virtual.size, before, after;
		if(real.isNil or: { p.isString.not }) { ^p };
		i = p.find(virtual);
		if(i.isNil) { ^p };
		out = "";
		while { i.notNil } {
			before = if(i > 0) { p[i - 1] } { $  };
			after = if(i + n < p.size) { p[i + n] } { $/ };
			if(this.isNameChar(before) or: { this.isNameChar(after) }) {
				out = out ++ p.copyRange(from, i + n - 1);
			} {
				if(i > from) { out = out ++ p.copyRange(from, i - 1) };
				out = out ++ real;
			};
			from = i + n;
			i = p.find(virtual, false, from);
		};
		if(from < p.size) { out = out ++ p.copyRange(from, p.size - 1) };
		^out
	}

	// an OSC message (an array): its string arguments
	*mappedMsg { |msg|
		if(real.isNil) { ^msg };
		^msg.asArray.collect { |a| if(a.isString) { this.mapped(a) } { a } }
	}
}

+ String {
	standardizePath { ^NornsVirtualHome.mapped(this).prVhStandardizePath }
	prVhStandardizePath { _String_StandardizePath ^this.primitiveFailed }
	realPath { ^NornsVirtualHome.mapped(this).prVhRealPath }
	prVhRealPath { _String_RealPath ^this.primitiveFailed }
	pathMatch { ^NornsVirtualHome.mapped(this).prVhPathMatch }
	prVhPathMatch { _StringPathMatch ^this.primitiveFailed }
	systemCmd { ^NornsVirtualHome.mapped(this).prVhSystemCmd }
	prVhSystemCmd { _String_System ^this.primitiveFailed }
	unixCmd { arg action, postOutput = true;
		var pid;
		pid = NornsVirtualHome.mapped(this).prUnixCmd(postOutput);
		if(action.notNil) {
			unixCmdActions.put(pid, action);
		};
		^pid;
	}
	unixCmdGetStdOut { arg maxLineLength = 1024;
		var pipe, lines, line;
		pipe = Pipe.new(NornsVirtualHome.mapped(this), "r");
		lines = "";
		line = pipe.getLine(maxLineLength);
		while({ line.notNil }, { lines = lines ++ line ++ "\n"; line = pipe.getLine; });
		pipe.close;
		^lines;
	}
}

+ File {
	*delete { arg pathName; ^this.prVhDelete(NornsVirtualHome.mapped(pathName)) }
	*prVhDelete { arg pathName; _FileDelete ^this.primitiveFailed }
	*deleteAll { arg pathName; ^this.prVhDeleteAll(NornsVirtualHome.mapped(pathName)) }
	*prVhDeleteAll { arg pathName; _FileDeleteAll ^this.primitiveFailed }
	*mtime { arg pathName; ^this.prVhMTime(NornsVirtualHome.mapped(pathName)) }
	*prVhMTime { arg pathName; _FileMTime ^this.primitiveFailed }
	*exists { arg pathName; ^this.prVhExists(NornsVirtualHome.mapped(pathName)) }
	*prVhExists { arg pathName; _FileExists ^this.primitiveFailed }
	*realpath { arg pathName; ^this.prVhRealpath(NornsVirtualHome.mapped(pathName)) }
	*prVhRealpath { arg pathName; _FileRealPath ^this.primitiveFailed }
	*mkdir { arg pathName; ^this.prVhMkdir(NornsVirtualHome.mapped(pathName)) }
	*prVhMkdir { arg pathName; _FileMkDir ^this.primitiveFailed }
	*copy { arg pathNameFrom, pathNameTo; ^this.prVhCopy(NornsVirtualHome.mapped(pathNameFrom), NornsVirtualHome.mapped(pathNameTo)) }
	*prVhCopy { arg pathNameFrom, pathNameTo; _FileCopy ^this.primitiveFailed }
	*prType { arg pathName; ^this.prVhType(NornsVirtualHome.mapped(pathName)) }
	*prVhType { arg pathName; _FileType ^this.primitiveFailed }
	*fileSize { arg pathName; ^this.prVhFileSize(NornsVirtualHome.mapped(pathName)) }
	*prVhFileSize { arg pathName; _FileSize ^this.primitiveFailed }
	prOpen { arg pathName, mode; ^this.prVhOpen(NornsVirtualHome.mapped(pathName), mode) }
	prVhOpen { arg pathName, mode; _FileOpen ^this.primitiveFailed }
}

+ SoundFile {
	prOpenRead { arg pathName; ^this.prVhOpenRead(NornsVirtualHome.mapped(pathName)) }
	prVhOpenRead { arg pathName; _SFOpenRead ^this.primitiveFailed }
	prOpenWrite { arg pathName; ^this.prVhOpenWrite(NornsVirtualHome.mapped(pathName)) }
	prVhOpenWrite { arg pathName; _SFOpenWrite ^this.primitiveFailed }
}

+ Server {
	sendMsg { |... msg| addr.sendMsg(*NornsVirtualHome.mappedMsg(msg)) }
	sendBundle { |time ... msgs| addr.sendBundle(time, *msgs.collect { |m| NornsVirtualHome.mappedMsg(m) }) }
	listSendMsg { |msg| addr.sendMsg(*NornsVirtualHome.mappedMsg(msg)) }
	listSendBundle { |time, msgs| addr.sendBundle(time, *(msgs.asArray.collect { |m| NornsVirtualHome.mappedMsg(m) })) }
	sendMsgSync { |condition ... args|
		var cmdName, resp;
		if(condition.isNil) { condition = Condition.new };
		args = NornsVirtualHome.mappedMsg(args);
		cmdName = args[0].asString;
		if(cmdName[0] != $/) { cmdName = cmdName.insert(0, $/) };
		resp = OSCFunc({|msg|
			if(msg[1].asString == cmdName) {
				resp.free;
				condition.test = true;
				condition.signal;
			};
		}, '/done', addr);
		condition.test = false;
		addr.sendBundle(nil, args);
		condition.wait;
	}
}
