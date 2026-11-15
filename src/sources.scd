// Input sources and the mixer's source/master levels.
//
// Live: SoundIn 1-2 -> source bus. Route an app (YouTube in a browser)
// to SuperCollider's inputs with scripts/route-app.sh.
// File: any format; non-wav/aiff/flac is converted with ffmpeg first.
// The source bus feeds the analyser and the monitor (what you hear of
// the source through SuperCollider).
~sb.addParam(\inGain, \Source, ControlSpec(0, 4, \amp), 1,
	~sb.setOnSynth(\srcSynth), "in gain");
~sb.addParam(\demoBpm, \Source, ControlSpec(70, 170, \lin, 1), 104,
	~sb.setOnSynth(\srcSynth), "demo bpm");
~sb.addParam(\srcLevel, \Mixer, ControlSpec(0, 1.5, \amp), 1,
	~sb.setOnSynth(\monSynth), "source");
~sb.addParam(\master, \Mixer, ControlSpec(0, 1.5, \amp), 0.8,
	{ |key, value, sb|
		[\monSynth, \fxSynth].do { |k| sb[k] !? { |syn| syn.set(key, value) } }
	}, "master");

~sb.defs.add({
	SynthDef(\sb_live, { |out, inGain = 1|
		Out.ar(out, SoundIn.ar([0, 1]) * inGain.lag(0.05));
	}).add;
	[1, 2].do { |n|
		SynthDef(("sb_file" ++ n).asSymbol, { |out, buf, inGain = 1|
			var sig = PlayBuf.ar(n, buf, BufRateScale.kr(buf), loop: 1);
			if(n == 1) { sig = sig ! 2 };
			Out.ar(out, sig * inGain.lag(0.05));
		}).add;
	};
	// Demo groove: drums plus a chord pad, Am F C G, one chord per bar.
	// Something to jam with before routing YouTube; also the test input.
	SynthDef(\sb_demo, { |out, inGain = 1, demoBpm = 104|
		var t16 = Impulse.kr(demoBpm / 60 * 4);
		var step = PulseCount.kr(t16) - 1;
		var s16 = step % 16, bar = (step / 16).floor % 4;
		var pat = { |steps| t16 * Select.kr(s16, steps) };
		var kickT = pat.([1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1]);
		var snareT = pat.([0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0]);
		var hatT = pat.([1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 1, 1]);
		var stabT = pat.([0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0]);
		var chords = [[57, 60, 64], [57, 60, 65], [55, 60, 64], [55, 59, 62]];
		var kick = SinOsc.ar(EnvGen.kr(Env([160, 48], [0.06], \exp), kickT))
			* EnvGen.ar(Env.perc(0.001, 0.35), kickT);
		var snare = BPF.ar(WhiteNoise.ar, 1800, 0.8) * EnvGen.ar(Env.perc(0.001, 0.16), snareT) * 1.5;
		var hat = HPF.ar(WhiteNoise.ar, 8000) * EnvGen.ar(Env.perc(0.001, 0.04), hatT) * 0.35;
		var notes = 3.collect { |i| Select.kr(bar, chords.collect(_[i])) };
		var pad = LPF.ar(Saw.ar(notes.midicps * [[1, 1.005]]).sum, 1600) * 0.08;
		var stab = LPF.ar(Pulse.ar(notes.midicps * 2, 0.3).sum, 2500)
			* EnvGen.ar(Env.perc(0.002, 0.18), stabT) * 0.12;
		var sig = (kick * 0.8) + snare + hat;
		Out.ar(out, (sig ! 2 + pad.sum + (stab ! 2)) * inGain.lag(0.05) * 0.5);
	}).add;
	SynthDef(\sb_monitor, { |in, out = 0, srcLevel = 1, master = 0.8|
		Out.ar(out, In.ar(in, 2) * srcLevel.lag(0.05) * master.lag(0.05));
	}).add;
});

~sb.stopSource = { |self|
	self.srcSynth !? { |syn| syn.free };
	self.srcSynth = nil;
};

~sb.useLive = { |self|
	self.stopSource;
	self.srcSynth = Synth(\sb_live,
		[out: self.buses[\src], inGain: self.getParam(\inGain)], self.grp[\src]);
	self.sourceName = "live input";
	// the app is usually still audible on its own: do not double it
	// (scripts/route-app.sh --through takes it off the speakers instead)
	self.setParam(\srcLevel, 0);
	self.changed(\source);
};

~sb.useDemo = { |self|
	self.stopSource;
	self.srcSynth = Synth(\sb_demo, [out: self.buses[\src],
		inGain: self.getParam(\inGain), demoBpm: self.getParam(\demoBpm)], self.grp[\src]);
	self.sourceName = "demo groove";
	self.setParam(\srcLevel, 1);
	self.changed(\source);
};

~sb.playBuffer = { |self, buf, name|
	self.stopSource;
	self.fileBuf !? { |old| if(old != buf) { old.free } };
	self.fileBuf = buf;
	self.srcSynth = Synth(("sb_file" ++ buf.numChannels.clip(1, 2)).asSymbol,
		[out: self.buses[\src], buf: buf, inGain: self.getParam(\inGain)], self.grp[\src]);
	self.sourceName = name;
	self.setParam(\srcLevel, 1);
	self.changed(\source);
};

~sb.useFile = { |self, path|
	var s = Server.default;
	var ext = (path.splitext[1] ? "").toLower;
	var out = Platform.defaultTempDir +/+ "sb_%.wav".format(path.hash.abs);
	var read = { |p|
		Buffer.read(s, p, action: { |buf|
			if(buf.numFrames.isNil or: { buf.numFrames == 0 }) {
				"sb: could not read %".format(p).warn;
			} {
				self.playBuffer(buf, path.basename);
			};
		});
	};
	case
	{ File.exists(path).not } { "sb: no such file %".format(path).warn }
	{ ["wav", "wave", "aif", "aiff", "flac"].includesEqual(ext) } { read.(path) }
	{ true } {
		"sb: converting % with ffmpeg".format(path.basename).postln;
		"ffmpeg -nostdin -y -loglevel error -i % -ac 2 -ar 48000 %"
		.format(path.shellQuote, out.shellQuote)
		.unixCmd({ |code|
			if(code == 0) { read.(out) } { "sb: ffmpeg failed (%) for %".format(code, path).warn };
		}, false);
	};
};

~sb.starters.add([\sources, { |sb, s|
	var file = "SB_FILE".getenv, kind = "SB_SOURCE".getenv ? "demo";
	sb.monSynth = Synth(\sb_monitor,
		[in: sb.buses[\src], out: sb.outBus, srcLevel: sb.getParam(\srcLevel), master: sb.getParam(\master)],
		sb.grp[\mon]);
	case
	{ file.notNil and: { file.size > 0 } } { sb.useFile(file) }
	{ kind == "live" } { sb.useLive }
	{ true } { sb.useDemo };
}]);
