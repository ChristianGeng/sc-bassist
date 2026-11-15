// Drone layer: a sustained root + fifth that glides to the current
// chord (or key) root. Under a line with droneLevel, or alone with the
// style "drone" (the line goes quiet and the drone comes up).
~sb.addParam(\droneLevel, \Mixer, ControlSpec(0, 1.5, \amp), 0, { |k, v, sb| sb.updateDrone }, "drone");
~sb.addParam(\droneGlide, \Drone, ControlSpec(0.05, 8, \exp), 1.5, ~sb.setOnSynth(\droneSynth), "glide");
~sb.addParam(\droneMotion, \Drone, ControlSpec(0, 1), 0.4, ~sb.setOnSynth(\droneSynth), "motion");
~sb.addParam(\droneFifth, \Drone, ControlSpec(0, 1), 0.5, ~sb.setOnSynth(\droneSynth), "fifth");
~sb.addParam(\droneBright, \Drone, ControlSpec(100, 3000, \exp), 500, ~sb.setOnSynth(\droneSynth), "bright");

~sb.defs.add({
	SynthDef(\sb_drone, { |out, freq = 55, level = 0, droneGlide = 1.5, droneMotion = 0.4,
		droneFifth = 0.5, droneBright = 500|
		var f = freq.lag(droneGlide);
		var lfo = LFNoise2.kr(0.15 ! 2).range(1 - droneMotion, 1 + droneMotion);
		var saws = Saw.ar(f * [0.997, 1, 1.003]).sum
			+ (Saw.ar(f * 1.5 * [0.998, 1.002]).sum * droneFifth);
		var sig = RLPF.ar(saws, (droneBright * lfo).clip(60, 8000), 0.5) * 0.25;
		sig = sig + (SinOsc.ar(f) * 0.5);
		Out.ar(out, sig * level.lag(1.0) * 0.4);
	}).add;
});

// Pitch: chord root, else key root, else A; level: droneLevel, at least
// 0.7 when the style is "drone".
~sb.updateDrone = { |self|
	var st = self.state, th = self.theory;
	var idx = st[\chord] ?? { st[\keyIndex] } ?? { 9 };
	var level = self.getParam(\droneLevel);
	if(self.currentStyle == \drone) { level = level.max(0.7) };
	self.droneSynth !? { |syn|
		syn.set(\freq, th.rootMidi(th.chordRoot(idx)).midicps, \level, level);
	};
};

~sb.starters.add([\drone, { |sb, s|
	sb.droneSynth = Synth(\sb_drone, [out: sb.buses[\bass], level: 0] ++ sb.synthArgs(\Drone),
		sb.grp[\bass]);
}]);
