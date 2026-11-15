// Compile check: every .scd parses, every SynthDef builds. No server.
var root = "SB_ROOT".getenv;
var files;
(root +/+ "tests/harness.scd").load;
files = (root +/+ "src/*.scd").pathMatch ++ (root +/+ "tests/*.scd").pathMatch ++ [root +/+ "main.scd"];
files.do { |path|
	var code = File.readAllString(path);
	~t.ok(thisProcess.interpreter.compile(code).notNil, "parses: %".format(path.basename));
};
(root +/+ "src/load.scd").load;
~t.check(\synthdefs, {
	~sb.defs.do { |f| f.value(Server.default) };
	[\sb_live, \sb_file1, \sb_file2, \sb_demo, \sb_monitor, \sb_analyser,
		\sb_bass, \sb_drone, \sb_fx].do { |name|
		~t.ok(SynthDescLib.global[name].notNil, "SynthDef % builds".format(name));
	};
	~sb.fxSections.do { |sec|
		~sb.sectionParams(sec).do { |k|
			~t.ok(SynthDescLib.global[\sb_fx].controlNames.includes(k),
				"fx param % is a control of sb_fx".format(k));
		};
	};
});
~t.finish("compile");
