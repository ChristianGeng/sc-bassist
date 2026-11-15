// Minimal test harness: ~t.ok / ~t.eq record results, ~t.check runs a
// named body (an error fails the suite instead of hanging sclang),
// ~t.finish prints a summary and exits with 0 (all passed) or 1.
~t = (
	passed: 0, failed: List[], verbose: false,
	ok: { |self, cond, msg|
		if(cond == true) {
			self.passed = self.passed + 1;
			if(self.verbose) { "ok %".format(msg).postln };
		} {
			self.failed.add(msg);
			"FAIL: %".format(msg).postln;
		};
	},
	eq: { |self, got, want, msg|
		self.ok(got == want, "% (want %, got %)".format(msg, want, got));
	},
	check: { |self, name, body|
		body.try { |err|
			"ERROR in %: %".format(name, err.errorString).postln;
			self.failed.add(name ++ ": " ++ err.errorString);
		};
	},
	// Function coverage: wrap every function of ~sb and ~sb.theory with a
	// call counter (sclang has no line-coverage tool). finish writes the
	// counts to $SB_TEST_OUT/coverage-<suite>.txt; test.sh merges them.
	instrument: { |self, sb|
		var t = self;
		t.hits = t.hits ?? { () };
		[[\sb, sb], [\theory, sb.theory]].do { |pair|
			var ev = pair[1];
			ev.keys.asArray.do { |k|
				var f = ev[k], id = "%.%".format(pair[0], k).asSymbol;
				if(f.isKindOf(Function)) {
					t.hits[id] = 0;
					ev[k] = { |...args| t.hits[id] = t.hits[id] + 1; f.valueArray(args) };
				};
			};
		};
	},
	finish: { |self, name|
		var dir = "SB_TEST_OUT".getenv, file;
		if(self.hits.notNil and: { dir.notNil }) {
			file = File(dir +/+ "coverage-%.txt".format(name), "w");
			self.hits.keysValuesDo { |k, n| file.write("% %\n".format(k, n)) };
			file.close;
		};
		"\n%: % passed, % failed".format(name, self.passed, self.failed.size).postln;
		self.failed.do { |f| "  - %".format(f).postln };
		// exiting while the startup file is still running hangs sclang
		AppClock.sched(0.1, { (if(self.failed.isEmpty) { 0 } { 1 }).exit; nil });
	}
);
