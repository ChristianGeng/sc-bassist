// Core: namespace, parameter registry, server options, buses and groups.
//
// Every module adds SynthDef builders to ~sb.defs and start functions
// to ~sb.starters; main.scd boots the server and runs them in order.
// Every controllable value is a parameter: ~sb.setParam(\name, value)
// is the single entry point for the UI, OSC remote control and tests.
~sb = ~sb ? ();
~sb.defs = List[];
~sb.starters = List[];
~sb.params = ();
~sb.paramOrder = List[];
~sb.sections = List[];
~sb.state = (
	bpm: 0, beatDur: 0.6, beats: 0, beatInBar: 0, lastBeat: 0,
	keyIndex: nil, chord: nil, chordSt: nil, chroma: 0 ! 12,
	amp: 0, energy: 0, onsetTimes: List[], onsetRate: 0, brightness: 0, flatness: 0,
	styleSt: nil, suggested: nil, notes: 0, lastMidi: nil,
	inPeak: 0, outPeak: 0, features: 0
);
~sb.barShift = 0;

// apply: function(key, value, sb) that pushes the value to the engine.
// items: optional names for an integer parameter (shown as a menu).
// toggle: true for an on/off parameter (shown as a button).
~sb.addParam = { |self, key, section, spec, default, apply, label, items, toggle = false|
	if(self.sections.includes(section).not) { self.sections.add(section) };
	self.params[key] = (
		section: section, cspec: spec.asSpec, val: default, apply: apply,
		label: label ? key.asString, items: items, toggle: toggle
	);
	self.paramOrder.add(key);
	key
};

~sb.getParam = { |self, key| self.params[key][\val] };

~sb.setParam = { |self, key, value|
	var p = self.params[key];
	if(p.isNil) {
		"sb: unknown parameter %".format(key).warn;
		nil
	} {
		value = p[\cspec].constrain(value);
		p[\val] = value;
		p[\apply].value(key, value, self);
		self.changed(\param, key, value);
		value
	}
};

// Parameter list for a section, in definition order.
~sb.sectionParams = { |self, section|
	self.paramOrder.select { |k| self.params[k][\section] == section }
};

// Pairs [key, value, ...] of a section's parameters, for Synth creation.
~sb.synthArgs = { |self, section|
	self.sectionParams(section).collect { |k| [k, self.getParam(k)] }.flat
};

~sb.setOnSynth = { |self, synthKey|
	{ |key, value, sb| sb[synthKey] !? { |syn| syn.set(key, value) } }
};

~sb.configureServer = { |self, s|
	var o = s.options;
	"SB_SCSYNTH".getenv !? { |p| Server.program = p };
	"SB_PLUGINS".getenv !? { |p| o.ugenPluginsPath = p };
	"SB_DEVICE".getenv !? { |d| o.device = d };
	"SB_HWBUF".getenv !? { |n| o.hardwareBufferSize = n.asInteger };
	o.numInputBusChannels = 2;
	o.numOutputBusChannels = 2;
	o.memSize = 2 ** 16;
	s.latency = 0.05;
};

~sb.starters.add([\core, { |sb, s|
	sb.buses = (src: Bus.audio(s, 2), bass: Bus.audio(s, 2));
	// SB_SILENT (tests): write the mix to a private bus, never to the
	// hardware outputs, whatever the JACK/PipeWire auto-connect does
	sb.outBus = if("SB_SILENT".getenv.notNil) { Bus.audio(s, 2).index } { 0 };
	sb.grp = (
		src: Group.tail(s),
		ana: Group.tail(s),
		bass: Group.tail(s),
		fx: Group.tail(s),
		mon: Group.tail(s)
	);
}]);

~sb.shutdown = { |self|
	self.clockTask !? { |t| t.stop };
	self.grp = nil; // notes still scheduled on the clock see this and skip
	OSCdef.all.keys.do { |k| if(k.asString.beginsWith("sb_")) { OSCdef(k).free } };
	Server.default.freeAll;
};
