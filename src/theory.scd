// Music theory for the bassist: pure functions, no server needed.
//
// Chords and keys share one index: 0-11 = C..B major, 12-23 = C..B minor
// (the convention of KeyTrack). Notes are MIDI numbers.
// Style patterns are 16 steps (sixteenths) per bar; every entry is
// [step, kind, velocity, length in sixteenths, minimum energy].
// notesForBeat returns Events (at: fraction of the beat, len: beats).
~sb = ~sb ? ();
~sb.theory = (
	noteNames: ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"],
	qualities: (maj: [0, 4, 7], min: [0, 3, 7]),
	scales: (
		mixolydian: [0, 2, 4, 5, 7, 9, 10],
		dorian: [0, 2, 3, 5, 7, 9, 10]
	),
	styleNames: [\roots, \rootFifth, \octaves, \funk, \walking, \sparse, \runs, \drone],
	styles: (
		roots: [[0, \root, 1, 4, 0], [4, \root, 0.8, 4, 0.15],
			[8, \root, 0.9, 4, 0], [12, \root, 0.8, 4, 0.15]],
		rootFifth: [[0, \root, 1, 3, 0], [4, \fifth, 0.8, 3, 0.1],
			[8, \root, 0.9, 3, 0], [12, \fifth, 0.8, 3, 0.1]],
		octaves: (0, 2 .. 14).collect { |step, i|
			[step, if(i.even) { \root } { \octave }, if(i.even) { 0.95 } { 0.7 },
				1.5, if(step % 4 == 0) { 0 } { 0.25 }]
		},
		funk: [[0, \root, 1, 1, 0], [3, \octave, 0.6, 1, 0.3], [6, \root, 0.8, 1, 0.15],
			[7, \fifth, 0.6, 1, 0.4], [10, \root, 0.9, 1, 0], [12, \octave, 0.5, 0.5, 0.5],
			[14, \seventh, 0.7, 1, 0.3], [15, \approach, 0.6, 1, 0.5]],
		walking: [[0, \root, 1, 4, 0], [4, \third, 0.85, 4, 0],
			[8, \fifth, 0.9, 4, 0], [12, \approach, 0.8, 4, 0]],
		sparse: [[0, \root, 1, 14, 0], [10, \fifth, 0.6, 4, 0.6]]
	),

	noteName: { |self, pc| self.noteNames.wrapAt(pc.asInteger) },

	// "A min" for 21, "-" for nil.
	keyName: { |self, index|
		if(index.isNil) { "-" } {
			index = index.asInteger;
			self.noteName(index % 12) ++ if(index >= 12) { " min" } { " maj" }
		}
	},

	chordIndex: { |self, root, quality| (root.asInteger % 12) + if(quality == \min) { 12 } { 0 } },
	chordRoot: { |self, index| index.asInteger % 12 },
	chordQuality: { |self, index| if(index.asInteger >= 12) { \min } { \maj } },

	// Best major/minor triad for a 12-bin chroma vector, as a chord index.
	// nil when the chroma is (near) silent or flat.
	detectChord: { |self, chroma, minPeak = 0.05|
		var bestIndex, bestScore = inf.neg, mean;
		chroma = chroma.asArray;
		mean = chroma.sum / 12;
		if(chroma.maxItem < minPeak or: { chroma.maxItem < (mean * 1.3) }) { nil } {
			12.do { |root|
				[\maj, \min].do { |quality|
					var tones = self.qualities[quality];
					var score = tones.sum { |i| chroma.wrapAt(root + i) }
						+ (chroma.wrapAt(root) * 0.5) - (mean * 3.5);
					if(score > bestScore) {
						bestScore = score;
						bestIndex = self.chordIndex(root, quality);
					};
				};
			};
			bestIndex
		}
	},

	// Hysteresis: a new value replaces the current one only after it was
	// proposed `hold` times in a row. st is (cur:, cand:, n:) or nil.
	stabilize: { |self, st, value, hold = 4|
		st = st ?? { (cur: nil, cand: nil, n: 0) };
		if(value.notNil) {
			if(value == st.cur) {
				st.cand = nil;
				st.n = 0;
			} {
				if(value == st.cand) { st.n = st.n + 1 } { st.cand = value; st.n = 1 };
				if(st.n >= hold or: { st.cur.isNil }) {
					st.cur = value;
					st.cand = nil;
					st.n = 0;
				};
			};
		};
		st
	},

	// Map a raw tempo onto 70-180 BPM by octave folding; nil if implausible.
	foldBpm: { |self, bpm|
		if(bpm.isNil or: { bpm <= 10 } or: { bpm > 1000 }) { nil } {
			while { bpm < 70 } { bpm = bpm * 2 };
			while { bpm > 180 } { bpm = bpm / 2 };
			bpm
		}
	},

	// Amplitude (linear, 0..1) to energy 0..1 on a -50..-10 dB scale.
	energyFromAmp: { |self, amp|
		amp.max(1e-6).ampdb.linlin(-50, -10, 0, 1)
	},

	// Root pitch class to a MIDI note between G1 (31) and F#2 (42).
	rootMidi: { |self, pc|
		var m = 36 + (pc.asInteger % 12);
		if(m > 42) { m - 12 } { m }
	},

	kindInterval: { |self, kind, quality|
		switch(kind,
			\root, { 0 },
			\fifth, { 7 },
			\octave, { 12 },
			\third, { if(quality == \min) { 3 } { 4 } },
			\seventh, { 10 },
			\approach, { -1 },
			{ 0 }
		)
	},

	// Notes to play during one beat (beatInBar 0..3).
	// prev is the last MIDI note played (for runs and glides).
	notesForBeat: { |self, style, beatInBar, chord, energy, octave = 0, prev|
		var root = self.chordRoot(chord), quality = self.chordQuality(chord);
		var pattern, base;
		case
		{ style == \drone } { [] }
		{ style == \runs } {
			self.runNotes(beatInBar, root, quality, energy, prev, octave)
		}
		{ true } {
			pattern = self.styles[style] ?? { self.styles[\rootFifth] };
			base = self.rootMidi(root) + (12 * octave);
			pattern.select { |e|
				((e[0] div: 4) == beatInBar) and: { energy >= e[4] }
			}.collect { |e|
				(at: (e[0] % 4) / 4, midi: base + self.kindInterval(e[1], quality),
					vel: e[2], len: e[3] / 4, slide: false)
			}
		}
	},

	// Generative virtuoso line: stepwise through a chord scale, octave
	// leaps, ghost notes, slides, chromatic approach into the next bar.
	// Uses the thread's random generator: seed it for repeatable output.
	runNotes: { |self, beatInBar, root, quality, energy, prev, octave = 0|
		var scale = if(quality == \min) { self.scales[\dorian] } { self.scales[\mixolydian] };
		var sub = if(energy > 0.75) { 8 } { 4 };
		var base = self.rootMidi(root) + (12 * octave);
		var pool = (-1 .. 2).collect { |o| scale + base + (o * 12) }.flat
			.select { |m| m.inclusivelyBetween(base - 5, base + 24) }.sort;
		var cur = (prev ? base).clip(pool.first, pool.last);
		var idx = pool.indexIn(cur);
		var notes = List[];
		sub.do { |i|
			var midi, vel = rrand(0.55, 0.85), slide = 0.15.coin;
			var restChance = if(i == 0) { 0 } { 0.35 - (energy * 0.3) };
			if(restChance.coin.not) {
				case
				{ (beatInBar == 0) and: { i == 0 } } { midi = base; vel = 1; slide = false }
				{ (beatInBar == 3) and: { i == (sub - 1) } } {
					// leading tone into the next bar's root, nearest octave
					midi = [base - 1, base + 11].minItem { |m| (m - cur).abs };
				}
				{ (energy > 0.5) and: { 0.12.coin } } {
					midi = (cur + [12, -12].choose).clip(pool.first, pool.last);
				}
				{ true } {
					idx = (idx + [-2, -1, -1, 1, 1, 2].choose).clip(0, pool.size - 1);
					midi = pool[idx];
				};
				if(0.1.coin and: { i > 0 }) { vel = 0.3 }; // ghost note
				idx = pool.indexIn(midi);
				cur = midi;
				notes.add((at: i / sub, midi: midi, vel: vel, len: 0.9 / sub, slide: slide));
			};
		};
		notes.asArray
	},

	// BeatTrack often locks at double or half tempo. Fold its ticks like
	// the displayed tempo: every = play on every n-th tick, perTick =
	// beats per tick, dur = the folded beat period in seconds.
	tickPlan: { |self, bps|
		var raw = bps * 60, folded = self.foldBpm(raw) ? raw, ratio = folded / raw;
		(every: (1 / ratio).round.asInteger.max(1), perTick: ratio.round.asInteger.max(1),
			dur: 60 / folded)
	},

	// Follow mode without a locked beat tracker: should the internal clock
	// play a beat now? Only when no tick was detected for 1.5 tick periods
	// (a half/quarter-tempo tick fills in its own beats until then), the
	// input is not below the gate, and a beat is due one period after the
	// last beat from either source (so the phases never double up).
	freeRunDue: { |self, now, lastBeat, lastDetected, period, energy, gate, tickPeriod|
		((now - lastDetected) > ((tickPeriod ? period).max(period) * 1.5))
		and: { energy >= gate }
		and: { (now - lastBeat) >= (period - 0.005) }
	},

	// A detected tick right after a free-running beat replaces it
	// (true = skip playing this tick, the beat was already played).
	skipDetected: { |self, now, lastBeat, lastWasFree, period|
		lastWasFree and: { (now - lastBeat) < (period * 0.5) }
	},

	// Rule-based style suggestion from the source's feel.
	// f: (energy: 0..1, onsetRate: per second, brightness: 0..1)
	suggestStyle: { |self, f|
		case
		{ f[\energy] < 0.12 } { \drone }
		{ f[\onsetRate] < 1.0 } { \sparse }
		{ (f[\onsetRate] > 6) and: { f[\energy] > 0.6 } } { \runs }
		{ (f[\brightness] > 0.45) and: { f[\onsetRate] > 3 } } { \funk }
		{ f[\onsetRate] > 4 } { \octaves }
		{ true } { \rootFifth }
	}
);
