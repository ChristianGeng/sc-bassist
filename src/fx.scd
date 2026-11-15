// Effects on the bass bus (line + drone):
// drive -> envelope-following low-pass -> compressor -> chorus -> delay
// -> reverb -> master -> limiter. Every stage has a click-free bypass.
var fx ={ |key, section, spec, default, label, items, toggle = false|
	~sb.addParam(key, section, spec, default, ~sb.setOnSynth(\fxSynth), label, items, toggle);
};
var onOff = { |key, section, default|
	fx.(key, section, ControlSpec(0, 1, \lin, 1), default, "on", nil, true);
};
onOff.(\driveOn, \Drive, 1);
fx.(\drive, \Drive, ControlSpec(0, 1), 0.25, "amount");
fx.(\driveTone, \Drive, ControlSpec(500, 8000, \exp), 3000, "tone");
onOff.(\filtOn, \Filter, 0);
fx.(\fCutoff, \Filter, ControlSpec(80, 5000, \exp), 600, "cutoff");
fx.(\fRes, \Filter, ControlSpec(0, 3.5), 1.2, "reso");
fx.(\fEnv, \Filter, ControlSpec(0, 1), 0.5, "env amt");
onOff.(\compOn, \Comp, 1);
fx.(\cThresh, \Comp, ControlSpec(0.05, 1, \exp), 0.3, "thresh");
fx.(\cRatio, \Comp, ControlSpec(1, 12, \exp), 4, "ratio");
fx.(\cGain, \Comp, ControlSpec(0.5, 4, \exp), 1.5, "makeup");
onOff.(\chorusOn, \Chorus, 0);
fx.(\chRate, \Chorus, ControlSpec(0.05, 5, \exp), 0.6, "rate");
fx.(\chMix, \Chorus, ControlSpec(0, 1), 0.4, "mix");
onOff.(\delayOn, \Delay, 0);
fx.(\dTime, \Delay, ControlSpec(0.05, 1.5, \exp), 0.375, "time");
fx.(\dFb, \Delay, ControlSpec(0, 0.9), 0.35, "feedback");
fx.(\dMix, \Delay, ControlSpec(0, 1), 0.25, "mix");
onOff.(\verbOn, \Reverb, 0);
fx.(\vRoom, \Reverb, ControlSpec(0, 1), 0.5, "room");
fx.(\vMix, \Reverb, ControlSpec(0, 1), 0.2, "mix");

~sb.fxSections = [\Drive, \Filter, \Comp, \Chorus, \Delay, \Reverb];

~sb.defs.add({
	SynthDef(\sb_fx, { |bus, out = 0, master = 0.8, bassLevel = 0.5,
		driveOn = 1, drive = 0.25, driveTone = 3000,
		filtOn = 0, fCutoff = 600, fRes = 1.2, fEnv = 0.5,
		compOn = 1, cThresh = 0.3, cRatio = 4, cGain = 1.5,
		chorusOn = 0, chRate = 0.6, chMix = 0.4,
		delayOn = 0, dTime = 0.375, dFb = 0.35, dMix = 0.25,
		verbOn = 0, vRoom = 0.5, vMix = 0.2|
		var bypass = { |on, dry, wet| var o = on.lag(0.05); (wet * o) + (dry * (1 - o)) };
		var sig = In.ar(bus, 2), wet, env, decay;
		// drive
		wet = LPF.ar((sig * (1 + (drive * 30))).tanh, driveTone) * (1 / (1 + (drive * 2)));
		sig = bypass.(driveOn, sig, wet);
		// envelope-following low-pass
		env = Amplitude.kr(sig.sum, 0.005, 0.2);
		wet = MoogFF.ar(sig, (fCutoff * (1 + (fEnv * 12 * env))).clip(40, 16000), fRes);
		sig = bypass.(filtOn, sig, wet);
		// compressor
		wet = Compander.ar(sig, sig, cThresh, 1, 1 / cRatio, 0.005, 0.12) * cGain;
		sig = bypass.(compOn, sig, wet);
		// chorus
		wet = sig + DelayC.ar(sig, 0.03, SinOsc.kr(chRate, [0, pi / 2]).range(0.004, 0.018));
		sig = bypass.(chorusOn, sig, (sig * (1 - chMix)) + (wet * 0.5 * chMix));
		// delay: decay time for the feedback amount
		decay = dTime * (-6.9 / dFb.max(0.01).log);
		wet = sig + (CombC.ar(sig, 1.5, dTime.lag(0.1), decay) * dMix);
		sig = bypass.(delayOn, sig, wet);
		// reverb
		wet = FreeVerb2.ar(sig[0], sig[1], vMix, vRoom, 0.5);
		sig = bypass.(verbOn, sig, wet);
		sig = Limiter.ar(sig * bassLevel.lag(0.05) * master.lag(0.05), 0.95, 0.01);
		SendReply.kr(Impulse.kr(15), '/sb/out', Amplitude.kr(sig.sum * 0.5, 0.001, 0.3));
		Out.ar(out, sig);
	}).add;
});

~sb.starters.add([\fx, { |sb, s|
	OSCdef(\sb_out, { |msg| sb.state[\outPeak] = msg[3] }, '/sb/out');
	sb.fxSynth = Synth(\sb_fx, [bus: sb.buses[\bass], out: sb.outBus, master: sb.getParam(\master),
		bassLevel: sb.getParam(\bassLevel)]
		++ sb.fxSections.collect { |sec| sb.synthArgs(sec) }.flat, sb.grp[\fx]);
}]);
