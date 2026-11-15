// UI test: builds the window offscreen (no server), checks that
// parameter changes from outside reach the widgets, and saves a
// screenshot to $SB_TEST_OUT/ui.png.
var root = "SB_ROOT".getenv;
(root +/+ "tests/harness.scd").load;
(root +/+ "src/load.scd").load;
~t.instrument(~sb);
~t.check(\build, {
	var win = ~sb.buildUi;
	~t.ok(win.isKindOf(Window), "window is built");
	~t.eq(~sb.uiUpdaters.size, ~sb.paramOrder.size, "every parameter has a widget");
	~sb.state[\bpm] = 104;
	~sb.state[\keyIndex] = 21;
	~sb.state[\chord] = 5;
	~sb.state[\energy] = 0.6;
	~sb.state[\suggested] = \funk;
	~sb.sourceName = "demo groove";
});
AppClock.sched(0.5, {
	~t.check(\updates, {
		~sb.setParam(\style, 3);
		~sb.setParam(\delayOn, 1);
		~sb.setParam(\cutoff, 1500);
	});
	nil
});
AppClock.sched(1.0, {
	~t.check(\widgets, {
		// the dependant defers widget updates; they have run by now
		var win = ~sb.win, path = "SB_TEST_OUT".getenv +/+ "ui.png";
		var all = List[];
		var collect = { |v| all.add(v); v.children.do(collect) };
		win.view.children.do(collect);
		~t.ok(all.select { |v| v.isKindOf(Knob) }.size > 30, "knobs are shown");
		~t.ok(all.any { |v| v.isKindOf(PopUpMenu) and: { v.items.includesEqual("funk") } and: { v.value == 3 } },
			"style menu follows setParam");
		~t.ok(all.any { |v| v.isKindOf(StaticText) and: { v.string == "104" } }, "BPM is displayed");
		~t.ok(all.any { |v| v.isKindOf(StaticText) and: { v.string == "F maj" } }, "chord is displayed");
		Image.fromWindow(win).write(path);
		~t.ok(File.exists(path), "screenshot written");
		win.close;
	});
	~t.finish("ui");
	nil
});
