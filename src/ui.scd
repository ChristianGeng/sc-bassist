// The window. Controls are generated from the parameter registry:
// toggles -> buttons, named integers -> menus, the rest -> knobs.
// Parameter changes from elsewhere (OSC, "surprise me") come back in
// through the dependant, so the UI always shows the engine's state.
~sb.uiColors = (
	bg: Color.grey(0.12), panel: Color.grey(0.18), text: Color.grey(0.85),
	dim: Color.grey(0.55), accent: Color(0.35, 0.85, 0.55), hot: Color(1, 0.55, 0.2)
);

~sb.fmtValue = { |self, v|
	if(v.abs >= 100) { v.round(1).asInteger.asString } { v.round(0.01).asString }
};

~sb.makeControl = { |self, key, updaters|
	var p = self.params[key], c = self.uiColors, sb = self;
	var label = { StaticText().string_(p[\label]).stringColor_(c[\dim]).align_(\center) };
	case
	{ p[\toggle] } {
		var b = Button().states_([
			[p[\label], c[\text], Color.grey(0.28)],
			[p[\label], Color.black, c[\accent]]
		]).value_(p[\val].asInteger).action_({ |b| sb.setParam(key, b.value) });
		updaters[key] = { |v| b.value = v.asInteger };
		b
	}
	{ p[\items].notNil } {
		var m = PopUpMenu().items_(p[\items].collect(_.asString))
		.value_(p[\val].asInteger).action_({ |m| sb.setParam(key, m.value) });
		updaters[key] = { |v| m.value = v.asInteger };
		VLayout(label.(), m)
	}
	{ true } {
		var t = StaticText().string_(sb.fmtValue(p[\val])).stringColor_(c[\text]).align_(\center);
		var k = Knob().value_(p[\cspec].unmap(p[\val])).fixedSize_(Size(46, 46))
		.color_([Color.grey(0.3), c[\accent], Color.grey(0.2), c[\text]]);
		k.action = { |k| t.string = sb.fmtValue(sb.setParam(key, p[\cspec].map(k.value))) };
		updaters[key] = { |v| k.value = p[\cspec].unmap(v); t.string = sb.fmtValue(v) };
		VLayout(label.(), [k, align: \center], t)
	}
};

~sb.makeSection = { |self, section, updaters|
	var c = self.uiColors;
	View().background_(c[\panel]).layout_(VLayout(
		StaticText().string_(section.asString).stringColor_(c[\hot])
		.font_(Font.default.copy.size_(13).bold_(true)),
		HLayout(*self.sectionParams(section).collect { |k| self.makeControl(k, updaters) })
	).margins_(6).spacing_(4))
};

~sb.buildUi = { |self|
	var sb = self, c = self.uiColors, th = self.theory, st = self.state;
	var updaters = (), win, dep, task, row, big, button, lamps, srcLabel;
	var bpmL, keyL, chordL, styleL, onsetL, notesL, energyM, inM, outM;
	big = { |text| StaticText().string_(text).stringColor_(c[\text])
		.font_(Font.default.copy.size_(18).bold_(true)) };
	button = { |text, action| Button().states_([[text, c[\text], Color.grey(0.28)]]).action_(action) };
	row = { |sections| HLayout(*sections.collect { |s| self.makeSection(s, updaters) }) };

	win = Window("sc-bassist", Rect(60, 60, 1240, 760)).background_(c[\bg]);
	srcLabel = StaticText().string_(sb.sourceName ? "-").stringColor_(c[\dim]);
	bpmL = big.("--"); keyL = big.("-"); chordL = big.("-"); styleL = big.("-");
	onsetL = StaticText().stringColor_(c[\dim]); notesL = StaticText().stringColor_(c[\dim]);
	energyM = LevelIndicator().fixedWidth_(16).fixedHeight_(56);
	inM = LevelIndicator().fixedWidth_(10).fixedHeight_(56);
	outM = LevelIndicator().fixedWidth_(10).fixedHeight_(56);
	lamps = 4.collect { View().fixedSize_(Size(22, 22)).background_(Color.grey(0.25)) };

	win.layout = VLayout(
		HLayout(
			StaticText().string_("sc-bassist").stringColor_(c[\accent])
			.font_(Font.default.copy.size_(20).bold_(true)),
			button.("Demo groove", { sb.useDemo }),
			button.("Live input", { sb.useLive }),
			button.("Open file...", { Dialog.openPanel({ |path| sb.useFile(path) }) }),
			srcLabel, nil,
			button.("Tap tempo", { sb.tap }),
			button.("Shift beat 1", { sb.shiftDownbeat }),
			Button().states_([["Surprise me!", Color.black, c[\hot]]]).action_({ sb.surprise })
		),
		View().background_(c[\panel]).fixedHeight_(96).layout_(HLayout(
			GridLayout.rows(
				["BPM", "key", "chord", "style", "beat"].collect { |s|
					StaticText().string_(s).stringColor_(c[\dim])
				},
				[bpmL.fixedWidth_(70), keyL.fixedWidth_(100), chordL.fixedWidth_(200),
					styleL.fixedWidth_(300), HLayout(*lamps).spacing_(5)]
			).hSpacing_(16),
			VLayout(onsetL, notesL), nil,
			VLayout(StaticText().string_("energy  in  out").stringColor_(c[\dim]),
				HLayout(energyM, inM, outM))
		).margins_(8)),
		row.([\Player, \Harmony, \Mixer]),
		row.([\Voice, \Drone, \Source, \Analysis]),
		row.(self.fxSections)
	).margins_(10).spacing_(8);

	dep = { |obj, what, key, val|
		case
		{ what == \param } { { updaters[key] !? { |f| f.value(val) } }.defer }
		{ what == \source } { { srcLabel.string = sb.sourceName ? "-" }.defer };
	};
	sb.addDependant(dep);

	task = Routine {
		loop {
			var now = Main.elapsedTime, chord = sb.currentChord, style = sb.currentStyle;
			var sug = st[\suggested];
			bpmL.string = if(st[\bpm].notNil and: { st[\bpm] > 0 }) { st[\bpm].round(1).asString } { "--" };
			keyL.string = th.keyName(st[\keyIndex]);
			chordL.string = th.keyName(chord) ++ if(sb.getParam(\lockChord) > 0) { " (locked)" } { "" };
			styleL.string = style.asString ++ if(sug.notNil and: { sug != style }) { "  (hears: %)".format(sug) } { "" };
			onsetL.string = "onsets/s %".format(st[\onsetRate].round(0.5));
			notesL.string = "notes %".format(st[\notes]);
			energyM.value = st[\energy];
			inM.value = st[\amp].max(0).sqrt;
			outM.value = st[\outPeak].max(0).sqrt;
			lamps.do { |l, i|
				l.background = if(i == st[\beatInBar] and: { (now - st[\lastBeat]) < 0.12 }) {
					if(i == 0) { c[\hot] } { c[\accent] }
				} { Color.grey(0.25) };
			};
			0.05.wait;
		}
	}.play(AppClock);

	win.onClose = {
		task.stop;
		sb.removeDependant(dep);
		if("SB_EXIT_ON_CLOSE".getenv.notNil) {
			sb.shutdown;
			Server.default.quit;
			{ 0.exit }.defer(0.5);
		};
	};
	sb.win = win;
	sb.uiUpdaters = updaters;
	win.front;
	win
};
