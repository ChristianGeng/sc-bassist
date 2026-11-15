// Unit tests: theory, parameter registry, player logic. No server.
var root = "SB_ROOT".getenv;
var th, chroma;
(root +/+ "tests/harness.scd").load;
(root +/+ "src/load.scd").load;
~t.instrument(~sb);
th = ~sb.theory;

// chroma with energy on the given pitch classes
chroma = { |pcs, weight = 1| (0 ! 12).collect { |v, i| if(pcs.includes(i)) { weight } { 0.05 } } };

~t.check(\names, {
	~t.eq(th.keyName(21), "A min", "keyName minor");
	~t.eq(th.keyName(7), "G maj", "keyName major");
	~t.eq(th.keyName(nil), "-", "keyName nil");
});

~t.check(\detectChord, {
	~t.eq(th.detectChord(chroma.([0, 4, 7])), 0, "C major triad");
	~t.eq(th.detectChord(chroma.([9, 0, 4])), 21, "A minor triad");
	~t.eq(th.detectChord(chroma.([7, 11, 2])), 7, "G major triad");
	~t.eq(th.detectChord(chroma.([5, 9, 0])), 5, "F major triad");
	~t.eq(th.detectChord(0 ! 12), nil, "silence gives no chord");
	~t.eq(th.detectChord(1 ! 12), nil, "flat chroma gives no chord");
});

~t.check(\stabilize, {
	var st = th.stabilize(nil, 3, 3);
	~t.eq(st[\cur], 3, "first value is taken at once");
	st = th.stabilize(st, 5, 3);
	st = th.stabilize(st, 5, 3);
	~t.eq(st[\cur], 3, "change needs hold frames");
	st = th.stabilize(st, 5, 3);
	~t.eq(st[\cur], 5, "change after hold frames");
	st = th.stabilize(st, 7, 3);
	st = th.stabilize(st, 5, 3);
	st = th.stabilize(st, 7, 3);
	~t.eq(st[\cur], 5, "flicker does not switch");
	~t.eq(th.stabilize(st, nil, 3)[\cur], 5, "nil keeps the current value");
});

~t.check(\tempo, {
	~t.eq(th.foldBpm(50), 100, "fold up");
	~t.eq(th.foldBpm(240), 120, "fold down");
	~t.eq(th.foldBpm(120), 120, "in range");
	~t.eq(th.foldBpm(0), nil, "zero is no tempo");
	~t.ok(th.energyFromAmp(0) == 0, "silence is zero energy");
	~t.ok(th.energyFromAmp(1) == 1, "full scale is full energy");
});

~t.check(\patterns, {
	var notes = th.notesForBeat(\rootFifth, 0, 21, 0.5);
	~t.eq(notes.collect(_[\midi]), [33], "root-fifth beat 1 plays A1");
	notes = th.notesForBeat(\rootFifth, 1, 21, 0.5);
	~t.eq(notes.collect(_[\midi]), [40], "root-fifth beat 2 plays the fifth");
	~t.eq(th.notesForBeat(\walking, 1, 21, 0.5)[0][\midi], 36, "walking uses the minor third");
	~t.eq(th.notesForBeat(\walking, 1, 0, 0.5)[0][\midi], 40, "walking uses the major third");
	~t.ok(4.collect { |b| th.notesForBeat(\funk, b, 0, 0).size }.sum
		< 4.collect { |b| th.notesForBeat(\funk, b, 0, 1).size }.sum,
		"more energy, more notes");
	~t.eq(th.notesForBeat(\drone, 0, 0, 1), [], "drone style plays no line");
	~t.eq(th.notesForBeat(\rootFifth, 0, 21, 0.5, 1)[0][\midi], 45, "octave shift");
	th.styleNames.do { |style|
		4.do { |b|
			th.notesForBeat(style, b, 21, 1, 0, 33).do { |n|
				~t.ok(n[\at] >= 0 and: { n[\at] < 1 }, "% note starts within the beat".format(style));
				~t.ok(n[\midi].inclusivelyBetween(24, 72), "% note in bass range".format(style));
			};
		};
	};
});

~t.check(\runs, {
	var a, b, all = List[];
	thisThread.randSeed = 42;
	a = 4.collect { |beat| th.runNotes(beat, 9, \min, 0.9, 33) }.flat.collect(_[\midi]);
	thisThread.randSeed = 42;
	b = 4.collect { |beat| th.runNotes(beat, 9, \min, 0.9, 33) }.flat.collect(_[\midi]);
	~t.eq(a, b, "runs are repeatable with a seed");
	~t.ok(a.size > 16, "high energy plays 32nds (% notes per bar)".format(a.size));
	~t.eq(th.runNotes(0, 9, \min, 0.9, 40)[0][\midi], 33, "runs land on the root on beat 1");
	100.do { all.addAll(th.runNotes(1, 9, \min, 0.6, 33).collect(_[\midi])) };
	~t.ok(all.every { |m| m.inclusivelyBetween(28, 57) }, "runs stay in range");
	~t.ok(all.asSet.size > 5, "runs use many notes");
});

~t.check(\tickPlan, {
	var p = th.tickPlan(208 / 60);
	~t.eq([p[\every], p[\perTick]], [2, 1], "double-tempo lock: play every second tick");
	~t.ok((p[\dur] - (60 / 104)).abs < 1e-6, "double-tempo lock: beat period of 104 BPM");
	p = th.tickPlan(52 / 60);
	~t.eq([p[\every], p[\perTick]], [1, 2], "half-tempo lock: two beats per tick");
	p = th.tickPlan(120 / 60);
	~t.eq([p[\every], p[\perTick]], [1, 1], "in range: one beat per tick");
});

~t.check(\freeRun, {
	// now, lastBeat, lastDetected, period, energy, gate
	~t.eq(th.freeRunDue(10, 9.5, 9.5, 0.5, 0.5, 0.05), false, "tracker locked: no free-running beat");
	~t.eq(th.freeRunDue(10, 9.5, 8.0, 0.5, 0.5, 0.05), true, "tracker stale and beat due: play");
	~t.eq(th.freeRunDue(10, 9.8, 8.0, 0.5, 0.5, 0.05), false, "beat not due yet: wait (no doubles)");
	~t.eq(th.freeRunDue(10, 9.0, 8.0, 0.5, 0.01, 0.05), false, "input below gate: silent");
	~t.eq(th.freeRunDue(10, 9.0, 8.0, 0.5, 0.0, 0), true, "gate 0 never gates");
	// quarter-tempo tick every 2 s fills its own beats: no free run before 3 s
	~t.eq(th.freeRunDue(10, 9.5, 8.0, 0.5, 0.5, 0.05, 2.0), false,
		"slow ticks still fill in: free-running waits 1.5 tick periods");
	~t.eq(th.freeRunDue(11.5, 11.0, 8.0, 0.5, 0.5, 0.05, 2.0), true,
		"free-running after 1.5 tick periods without a tick");
	// 190 BPM detection: the period stays 60/190, not the folded 95 BPM
	~sb.state[\detectedDur] = 60 / 190;
	~t.eq(~sb.freeRunPeriod, 60 / 190, "free-running uses the detected period");
	~sb.state[\detectedDur] = nil;
	~t.eq(~sb.freeRunPeriod, 60 / ~sb.getParam(\bpm), "no detection yet: manual BPM");
	// now, lastBeat, lastWasFree, period
	~t.eq(th.skipDetected(10, 9.9, true, 0.5), true, "detected tick right after a free beat replaces it");
	~t.eq(th.skipDetected(10, 9.6, true, 0.5), false, "detected tick half a beat later plays");
	~t.eq(th.skipDetected(10, 9.9, false, 0.5), false, "detected ticks never skip each other");
});

~t.check(\suggestStyle, {
	~t.eq(th.suggestStyle((energy: 0.05, onsetRate: 0, brightness: 0)), \drone, "quiet -> drone");
	~t.eq(th.suggestStyle((energy: 0.5, onsetRate: 0.5, brightness: 0.2)), \sparse, "few onsets -> sparse");
	~t.eq(th.suggestStyle((energy: 0.8, onsetRate: 8, brightness: 0.5)), \runs, "busy and loud -> runs");
	~t.eq(th.suggestStyle((energy: 0.5, onsetRate: 4, brightness: 0.6)), \funk, "bright, mid density -> funk");
	~t.eq(th.suggestStyle((energy: 0.5, onsetRate: 2, brightness: 0.2)), \rootFifth, "default");
});

~t.check(\params, {
	var seen;
	~t.eq(~sb.setParam(\cutoff, 100000), 6000, "values are clipped to the spec");
	~t.eq(~sb.setParam(\nonsense, 1), nil, "unknown parameter is ignored");
	~sb.addDependant({ |obj, what, key, val| if(what == \param) { seen = [key, val] } });
	~sb.setParam(\density, 0.5);
	~t.eq(seen, [\density, 0.5], "changes notify dependants");
	~t.ok(~sb.paramOrder.size > 40, "registry is populated (% params)".format(~sb.paramOrder.size));
	~sb.paramOrder.do { |k|
		var p = ~sb.params[k];
		~t.ok(p[\cspec].constrain(p[\val]) == p[\val], "default of % within its spec".format(k));
	};
	~sb.setParam(\style, th.styleNames.indexOf(\runs));
	~t.eq(~sb.currentStyle, \runs, "style parameter selects the style");
});

~t.check(\player, {
	~sb.setParam(\lockChord, 1);
	~sb.setParam(\lockRoot, 7);
	~sb.setParam(\lockQuality, 0);
	~t.eq(~sb.currentChord, 7, "locked chord is used");
	~sb.setParam(\lockChord, 0);
	~sb.state[\chord] = 5;
	~t.eq(~sb.currentChord, 5, "detected chord is used when unlocked");
	~sb.surprise;
	~t.ok(~sb.currentStyle.notNil, "surprise picks a style");
	~sb.shiftDownbeat;
	~t.eq(~sb.barShift, 1, "downbeat shift");
	3.do { ~sb.shiftDownbeat };
	~t.eq([~sb.barShift, ~sb.tickPhase], [0, 1], "four shifts move to the other tick");
});

~t.check(\tap, {
	var now = Main.elapsedTime;
	~sb.setParam(\sync, 0);
	~sb.taps = List[now - 1.0, now - 0.5];
	~sb.tap;
	~t.eq(~sb.getParam(\bpm), 120, "two taps 0.5 s apart give 120 BPM");
	~t.eq(~sb.getParam(\sync), 1, "tapping switches to manual sync");
});

~t.check(\registry, {
	var applied;
	~sb.setOnSynth(\nothing).value(\x, 1, ~sb); // no synth yet: must not fail
	~sb.addParam(\testParam, \Test, ControlSpec(0, 10), 5, { |k, v| applied = v }, "test");
	~t.eq(~sb.getParam(\testParam), 5, "addParam stores the default");
	~sb.setParam(\testParam, 7);
	~t.eq(applied, 7, "setParam calls the apply function");
	~t.ok(~sb.sections.includes(\Test), "addParam registers the section");
});

~t.finish("unit");
