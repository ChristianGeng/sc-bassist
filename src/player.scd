// The bassist: on every beat (detected, or from the internal clock in
// manual mode) it asks the theory module for that beat's notes and
// schedules them within the beat.
//
// density + react * input energy = how busy it plays (0..1).
// gate: below this input energy it stops in follow mode.
~sb.addParam(\bassOn, \Player, ControlSpec(0, 1, \lin, 1), 1, { }, "bass on", nil, true);
~sb.addParam(\style, \Player, ControlSpec(0, ~sb.theory.styleNames.size - 1, \lin, 1), 1,
	{ |k, v, sb| sb.updateDrone }, "style", ~sb.theory.styleNames);
~sb.addParam(\autoStyle, \Player, ControlSpec(0, 1, \lin, 1), 0, { }, "auto style", nil, true);
~sb.addParam(\sync, \Player, ControlSpec(0, 1, \lin, 1), 0, { }, "sync", [\follow, \manual]);
~sb.addParam(\bpm, \Player, ControlSpec(50, 220, \lin, 1), 104, { }, "manual bpm");
~sb.addParam(\octave, \Player, ControlSpec(-1, 1, \lin, 1), 0, { }, "octave");
~sb.addParam(\density, \Player, ControlSpec(0, 1), 0.3, { }, "density");
~sb.addParam(\react, \Player, ControlSpec(0, 1), 0.7, { }, "react");
~sb.addParam(\gate, \Player, ControlSpec(0, 0.5), 0.05, { }, "gate");
~sb.addParam(\lockChord, \Harmony, ControlSpec(0, 1, \lin, 1), 0, { |k, v, sb| sb.updateDrone },
	"lock chord", nil, true);
~sb.addParam(\lockRoot, \Harmony, ControlSpec(0, 11, \lin, 1), 9, { |k, v, sb| sb.updateDrone },
	"root", ~sb.theory.noteNames);
~sb.addParam(\lockQuality, \Harmony, ControlSpec(0, 1, \lin, 1), 1, { |k, v, sb| sb.updateDrone },
	"quality", [\maj, \min]);

~sb.currentStyle = { |self| self.theory.styleNames[self.getParam(\style).asInteger] };

~sb.currentChord = { |self|
	var th = self.theory;
	if(self.getParam(\lockChord) > 0) {
		th.chordIndex(self.getParam(\lockRoot), [\maj, \min][self.getParam(\lockQuality).asInteger])
	} {
		self.state[\chord] ?? { self.state[\keyIndex] } ?? { 21 }
	}
};

~sb.effectiveEnergy = { |self|
	(self.getParam(\density) + (self.state[\energy] * self.getParam(\react))).clip(0, 1)
};

~sb.onBeat = { |self, beatDur|
	var st = self.state, notes, manual = self.getParam(\sync) > 0;
	st[\beats] = st[\beats] + 1;
	st[\beatDur] = beatDur;
	st[\lastBeat] = Main.elapsedTime;
	st[\beatInBar] = (st[\beats] + self.barShift) % 4;
	self.updateDrone;
	if(self.getParam(\bassOn) > 0 and: { manual or: { st[\energy] >= self.getParam(\gate) } }) {
		notes = self.theory.notesForBeat(self.currentStyle, st[\beatInBar], self.currentChord,
			self.effectiveEnergy, self.getParam(\octave).asInteger, st[\lastMidi]);
		notes.do { |n|
			var delay = n[\at] * beatDur;
			if(delay <= 0) { self.playNote(n, beatDur) } {
				SystemClock.sched(delay, { self.playNote(n, beatDur); nil });
			};
		};
	};
};

// Internal clock: ticks at the manual BPM; only plays in manual mode.
~sb.startClock = { |self|
	self.clockTask !? { |t| t.stop };
	self.clockTask = Task {
		loop {
			var dur = 60 / self.getParam(\bpm);
			if(self.getParam(\sync) > 0) {
				self.state[\bpm] = self.getParam(\bpm);
				self.onBeat(dur);
			};
			dur.wait;
		}
	}.play(SystemClock);
};

// Tap tempo: average of the last taps; switches to manual sync.
~sb.tap = { |self|
	var now = Main.elapsedTime, taps = self.taps ?? { List[] }, iv;
	taps.removeAllSuchThat { |t| (now - t) > 3 };
	taps.add(now);
	self.taps = taps;
	if(taps.size >= 2) {
		iv = taps.differentiate.drop(1);
		self.setParam(\bpm, (60 / iv.mean).round);
		self.setParam(\sync, 1);
	};
};

// Move beat 1 of the bar (BeatTrack knows beats, not bars).
~sb.shiftDownbeat = { |self| self.barShift = (self.barShift + 1) % 4 };

~sb.updateAutoStyle = { |self|
	var st = self.state, th = self.theory;
	st[\suggested] = th.suggestStyle((energy: st[\energy], onsetRate: st[\onsetRate],
		brightness: st[\brightness]));
	st[\styleSt] = th.stabilize(st[\styleSt], st[\suggested], 40);
	if(self.getParam(\autoStyle) > 0 and: { st[\styleSt][\cur] != self.currentStyle }) {
		self.setParam(\style, th.styleNames.indexOf(st[\styleSt][\cur]));
	};
	self.updateDrone;
};

// "Surprise me": a random style, voice and effect setting.
~sb.surprise = { |self|
	var pick = { |key, lo, hi| self.setParam(key, rrand(lo, hi)) };
	self.setParam(\style, self.theory.styleNames.size.rand);
	self.setParam(\voice, self.voiceNames.size.rand);
	pick.(\cutoff, 250, 2500);
	pick.(\filtEnv, 0, 6);
	pick.(\glide, 0, 0.08);
	pick.(\density, 0.1, 0.8);
	[\driveOn, \chorusOn, \delayOn, \verbOn].do { |k| self.setParam(k, 0.4.coin.binaryValue) };
	pick.(\drive, 0.1, 0.8);
	self.changed(\surprise);
};

~sb.starters.add([\player, { |sb, s| sb.startClock }]);
