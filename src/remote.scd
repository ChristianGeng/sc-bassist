// OSC remote control on the language port (57120 by default):
//   /sb/set <param> <value>      any parameter, e.g. /sb/set style 6
//   /sb/do demo|live|tap|surprise|shift
//   /sb/do file <path>
// Same entry points as the UI, so a phone (TouchOSC, a web page) or a
// script can play it. Note: sclang listens on all interfaces.
~sb.starters.add([\remote, { |sb, s|
	OSCdef(\sb_set, { |msg|
		var key = msg[1].asSymbol;
		if(sb.params[key].notNil and: { msg[2].isNumber }) { sb.setParam(key, msg[2]) } {
			"sb: /sb/set ignored %".format(msg).warn;
		};
	}, '/sb/set');
	OSCdef(\sb_do, { |msg|
		switch(msg[1].asSymbol,
			\demo, { sb.useDemo },
			\live, { sb.useLive },
			\file, { sb.useFile(msg[2].asString) },
			\tap, { sb.tap },
			\surprise, { sb.surprise },
			\shift, { sb.shiftDownbeat },
			{ "sb: /sb/do ignored %".format(msg).warn }
		);
	}, '/sb/do');
}]);
