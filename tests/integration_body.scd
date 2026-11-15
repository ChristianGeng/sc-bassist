// Runs inside the booted engine (loaded via SB_AFTER by integration.scd).
var sb = ~sb, st = ~sb.state, t = ~t, th = ~sb.theory, s = Server.default;
t.verbose = true; // print measured values in CI logs
Routine {
	var notes, chords = List[], tmp, mp3, srcMax = 0, bassMax = 0, lockWait, beats0, notes0, iv, periods, stable = false, windowStart;
	t.check(\boot, {
		t.ok(s.serverRunning, "server runs");
		t.eq(sb.sourceName, "demo groove", "demo groove is the default source");
	});
	// the bass starts with the music, before the beat tracker has locked
	2.5.wait;
	t.ok(st[\notes] > 0, "plays during beat-tracker warm-up (% notes in 2.5 s)".format(st[\notes]));
	// BeatTrack wanders for 5-10 s (120 -> 150 -> 205 BPM ticks on this
	// groove) before it settles: wait until its beat period has been
	// stable for 5 s, then measure over a fixed window
	lockWait = 0;
	periods = List[];
	while { stable.not and: { lockWait < 25 } } {
		0.25.wait;
		lockWait = lockWait + 0.25;
		periods.add(st[\detectedDur] ? 0);
		if(periods.size > 20) { periods.removeAt(0) };
		stable = periods.size == 20 and: { periods.minItem > 0 }
			and: { (periods.maxItem / periods.minItem) < 1.03 };
	};
	t.ok(stable, "beat tracker settles within 25 s (% s)".format(lockWait));
	windowStart = Main.elapsedTime;
	beats0 = st[\beats];
	notes0 = st[\notes];
	// collect detected chords and peak levels while the demo plays
	80.do { |i|
		0.1.wait;
		if(i % 5 == 0) { st[\chord] !? { |c| chords.add(c) } };
		srcMax = srcMax.max(st[\amp]);
		bassMax = bassMax.max(st[\outPeak]);
	};
	t.check(\balance, {
		var db = (bassMax / srcMax.max(1e-6)).ampdb;
		t.ok(db.inclusivelyBetween(-9, 3),
			"bass vs source peak level within -9..+3 dB (% dB)".format(db.round(0.1)));
	});
	t.check(\analysis, {
		t.ok(st[\features] > 100, "feature frames arrive (%)".format(st[\features]));
		t.ok(st[\energy] > 0.2, "input energy is seen (%)".format(st[\energy].round(0.01)));
		t.ok((st[\beats] - beats0) > 8, "beats keep coming (% in 8 s)".format(st[\beats] - beats0));
		// from warm-up through the lock: no doubled beats
		iv = st[\beatTimes].select { |x| x >= windowStart }.asArray.differentiate.drop(1);
		t.ok((iv.median - (60 / 104)).abs < 0.06,
			"the bass plays at the groove's tempo, not a multiple (beat period % s, want %)"
			.format(iv.median.round(0.001), (60 / 104).round(0.001)));
		t.ok(iv.minItem > (iv.median * 0.4),
			"no doubled beats once settled (shortest % s, median % s)"
			.format(iv.minItem.round(0.001), iv.median.round(0.001)));
		t.ok(st[\bpm].notNil and: { (st[\bpm] - 104).abs < 6 },
			"tempo is about 104 BPM (%)".format(st[\bpm] !? (_.round(0.1))));
		t.ok(chords.size > 4, "chords are detected (%)".format(chords.collect(th.keyName(_)).asSet));
		t.ok(chords.every { |c| [21, 5, 0, 7, 9, 17].includes(c) },
			"chords fit Am F C G (%)".format(chords.collect(th.keyName(_)).asSet));
		t.ok(chords.asSet.size >= 2, "chord changes are followed");
	});
	t.check(\player, {
		t.ok((st[\notes] - notes0) > 8, "the bassist plays (% notes in 8 s)".format(st[\notes] - notes0));
		t.ok(bassMax > 0.01, "bass reaches the output (peak %)".format(bassMax.round(0.001)));
	});
	// manual clock, every style, drone, every effect on
	sb.setParam(\sync, 1);
	sb.setParam(\bpm, 150);
	[\driveOn, \filtOn, \compOn, \chorusOn, \delayOn, \verbOn].do { |k| sb.setParam(k, 1) };
	th.styleNames.do { |style|
		sb.setParam(\style, th.styleNames.indexOf(style));
		0.5.wait; // notes already scheduled by the previous style
		notes = st[\notes];
		1.2.wait;
		t.check(style, {
			if(style == \drone) {
				t.ok(st[\notes] == notes, "drone style plays no line");
			} {
				t.ok(st[\notes] > notes, "% plays in manual mode".format(style));
			};
		});
	};
	t.check(\drone, { t.ok(st[\outPeak] > 0.01, "drone is audible") });
	// OSC remote control on the language port
	NetAddr.localAddr.sendMsg('/sb/do', 'surprise');
	0.3.wait;
	NetAddr.localAddr.sendMsg('/sb/set', 'density', 0.9);
	0.3.wait;
	t.check(\remote, { t.eq(sb.getParam(\density).round(0.01), 0.9, "/sb/set sets a parameter") });
	t.check(\silent, {
		t.ok(sb.outBus >= s.options.firstPrivateBus, "tests write to a private bus, not the speakers");
	});
	// live input (analysed only: the mix goes to a private bus)
	sb.useLive;
	0.3.wait;
	t.check(\live, {
		t.eq(sb.sourceName, "live input", "live input is selected");
		t.eq(sb.getParam(\srcLevel), 0, "live input is not doubled on the monitor");
	});
	sb.useDemo;
	0.3.wait;
	// file input: a missing file is reported, a converted mp3 plays
	sb.useFile("/nonexistent.wav");
	t.check(\missingFile, { t.eq(sb.sourceName, "demo groove", "missing file keeps the source") });
	if("which ffmpeg".unixCmdGetStdOut.size > 0) {
		tmp = "SB_TEST_OUT".getenv;
		mp3 = tmp +/+ "tone.mp3";
		("ffmpeg -nostdin -y -loglevel error -f lavfi -i sine=frequency=110:duration=2 "
			++ mp3.shellQuote).systemCmd;
		sb.useFile(mp3);
		4.wait;
		t.check(\file, { t.eq(sb.sourceName, "tone.mp3", "mp3 is converted and played") });
	} {
		"integration: ffmpeg not found, skipping the mp3 check".postln;
	};
	sb.shutdown;
	s.quit;
	1.wait;
	t.finish("integration");
}.play(AppClock);
