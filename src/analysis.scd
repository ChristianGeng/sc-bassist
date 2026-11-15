// Analysis of the source bus. Core UGens only (no sc3-plugins):
// BeatTrack (beat ticks, tempo), KeyTrack (key), Chromagram (12 pitch
// classes -> chord), Amplitude (energy), Onsets (onset rate),
// SpecCentroid/SpecFlatness (brightness, noisiness).
// The synth sends OSC to the language; results land in ~sb.state.
~sb.addParam(\tempoLock, \Analysis, ControlSpec(0, 1, \lin, 1), 0,
	~sb.setOnSynth(\anaSynth), "tempo lock", nil, true);
~sb.addParam(\chordHold, \Analysis, ControlSpec(1, 40, \lin, 1), 6,
	{ }, "chord hold");
~sb.addParam(\onsetThresh, \Analysis, ControlSpec(0.05, 1, \lin), 0.4,
	~sb.setOnSynth(\anaSynth), "onset thr");

// 12 pitch-class energies from a bank of semitone-wide band-pass
// filters over four octaves (C2..B5), normalised to the loudest class.
// Core UGens only: Chromagram is not in every SuperCollider version.
~sb.chromaBank = { |self, sig|
	var bands = (36 .. 83).collect { |m|
		Amplitude.kr(BPF.ar(sig, m.midicps, 0.04), 0.01, 0.4)
	};
	var classes = 12.collect { |pc| bands[(pc, pc + 12 .. 47)].sum };
	var smoothed = classes.collect { |c| c.lag(0.3) };
	smoothed / (smoothed.reduce(\max) + 1e-6)
};

~sb.defs.add({
	SynthDef(\sb_analyser, { |in, tempoLock = 0, onsetThresh = 0.4, rate = 20|
		var sig = In.ar(in, 2).sum * 0.5;
		var fftBeat = FFT(LocalBuf(1024), sig);
		var fftKey = FFT(LocalBuf(4096), sig);
		var beat = BeatTrack.kr(fftBeat, tempoLock);
		var key = KeyTrack.kr(fftKey, 2.0, 0.5);
		var chroma = ~sb.chromaBank(sig);
		var amp = Amplitude.kr(sig, 0.01, 0.3);
		var onset = Onsets.kr(fftBeat, onsetThresh, \rcomplex);
		var centroid = SpecCentroid.kr(fftBeat);
		var flatness = SpecFlatness.kr(fftBeat);
		SendReply.kr(beat[0], '/sb/beat', beat[3]);
		SendReply.kr(onset, '/sb/onset', amp);
		SendReply.kr(Impulse.kr(rate), '/sb/feat', [key, amp, centroid, flatness] ++ chroma);
	}).add;
});

// v: [key, amp, centroid, flatness, chroma x 12]
~sb.onFeatures = { |self, v|
	var st = self.state, th = self.theory, now = Main.elapsedTime;
	st[\keyIndex] = v[0].asInteger;
	st[\amp] = v[1];
	st[\energy] = th.energyFromAmp(v[1]);
	st[\brightness] = v[2].explin(200, 5000, 0, 1);
	st[\flatness] = v[3];
	st[\chroma] = v.copyRange(4, 15);
	st[\features] = st[\features] + 1;
	// chroma is normalised per frame: only trust it when there is signal
	if(st[\energy] > 0.08) {
		st[\chordSt] = th.stabilize(st[\chordSt], th.detectChord(st[\chroma]),
			self.getParam(\chordHold));
		st[\chord] = st[\chordSt][\cur];
	};
	st[\onsetTimes].removeAllSuchThat { |t| (now - t) > 2 };
	st[\onsetRate] = st[\onsetTimes].size / 2;
	self.updateAutoStyle;
};

// BeatTrack tempo is in beats per second. The tick interval drives the
// player; the display shows it folded into 70-180 BPM.
~sb.onBeatDetected = { |self, bps|
	var st = self.state;
	if(bps > 0.5 and: { bps < 5 }) {
		if(self.getParam(\sync) == 0) {
			st[\bpm] = self.theory.foldBpm(bps * 60);
			self.onBeat(1 / bps);
		};
	};
};

~sb.starters.add([\analysis, { |sb, s|
	OSCdef(\sb_feat, { |msg| sb.onFeatures(msg.copyRange(3, msg.size - 1)) }, '/sb/feat');
	OSCdef(\sb_beat, { |msg| sb.onBeatDetected(msg[3]) }, '/sb/beat');
	OSCdef(\sb_onset, { |msg| sb.state[\onsetTimes].add(Main.elapsedTime) }, '/sb/onset');
	sb.anaSynth = Synth(\sb_analyser,
		[in: sb.buses[\src]] ++ sb.synthArgs(\Analysis), sb.grp[\ana]);
}]);
