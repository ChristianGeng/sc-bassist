// Bass voice: one timed note per synth, selectable timbre, glide from
// the previous pitch. Voice parameters apply to the next note.
~sb.voiceNames = [\saw, \pulse, \round, \fretless];
~sb.addParam(\voice, \Voice, ControlSpec(0, 3, \lin, 1), 0, { }, "voice", ~sb.voiceNames);
~sb.addParam(\cutoff, \Voice, ControlSpec(60, 6000, \exp), 700, { }, "cutoff");
~sb.addParam(\filtEnv, \Voice, ControlSpec(0, 8), 2, { }, "filter env");
~sb.addParam(\attack, \Voice, ControlSpec(0.001, 0.1, \exp), 0.004, { }, "attack");
~sb.addParam(\release, \Voice, ControlSpec(0.02, 1.5, \exp), 0.12, { }, "release");
~sb.addParam(\sub, \Voice, ControlSpec(0, 1), 0.4, { }, "sub");
~sb.addParam(\legato, \Voice, ControlSpec(0.2, 1.2), 0.85, { }, "legato");
~sb.addParam(\glide, \Voice, ControlSpec(0, 0.3, 4), 0, { }, "glide");
// mixer fader for line + drone, after the effects (drive and compressor
// would undo a level change made before them)
~sb.addParam(\bassLevel, \Mixer, ControlSpec(0, 1.5, \amp), 0.5, ~sb.setOnSynth(\fxSynth), "bass");

~sb.defs.add({
	SynthDef(\sb_bass, { |out, freq = 55, fromFreq = 55, glide = 0, amp = 0.5,
		dur = 0.25, voice = 0, cutoff = 700, filtEnv = 2, attack = 0.004,
		release = 0.12, sub = 0.4|
		var env = EnvGen.ar(Env([0, 1, 0.75, 0], [attack, dur, release], [2, -1, -4]),
			doneAction: 2);
		var f = EnvGen.kr(Env([fromFreq, freq], [glide.max(0.001)], \exp));
		var vib = 1 + (SinOsc.kr(5.5) * 0.004 * EnvGen.kr(Env([0, 0, 1], [0.15, 0.3])));
		var fenv = EnvGen.kr(Env.perc(0.002, 0.25));
		var sig = Select.ar(voice, [
			Saw.ar(f * [1, 1.004]).sum * 0.5,
			Pulse.ar(f, 0.3),
			SinOsc.ar(f) + (SinOsc.ar(f * 2) * 0.25) + (SinOsc.ar(f * 3) * 0.1),
			LFTri.ar(f * vib) + (SinOsc.ar(f * vib * 2) * 0.15)
		]);
		sig = RLPF.ar(sig, (cutoff * (1 + (filtEnv * fenv))).clip(30, 16000), 0.45);
		sig = sig + (SinOsc.ar(f) * sub);
		// level matched against the demo groove: the bass sits in the mix
		Out.ar(out, (sig * env * amp * 0.8) ! 2);
	}).add;
});

// n: (midi:, vel:, len: beats, slide: bool)
~sb.playNote = { |self, n, beatDur|
	var freq = n[\midi].midicps;
	var glide = self.getParam(\glide);
	var prev = self.state[\lastMidi];
	if(n[\slide] == true) { glide = glide.max(0.05) };
	if(self.grp.notNil) {
		Synth(\sb_bass, [
			out: self.buses[\bass], freq: freq,
			fromFreq: if(prev.notNil and: { glide > 0 }) { prev.midicps } { freq },
			glide: glide,
			amp: n[\vel],
			dur: (n[\len] * beatDur * self.getParam(\legato)).max(0.02),
			voice: self.getParam(\voice), cutoff: self.getParam(\cutoff),
			filtEnv: self.getParam(\filtEnv), attack: self.getParam(\attack),
			release: self.getParam(\release), sub: self.getParam(\sub)
		], self.grp[\bass]);
	};
	self.state[\lastMidi] = n[\midi];
	self.state[\notes] = self.state[\notes] + 1;
};
