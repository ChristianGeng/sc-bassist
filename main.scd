// sc-bassist entry point (start it with ./run.sh).
// Loads the modules, boots the server, starts the engine and opens the
// window unless SB_NOGUI is set. SB_AFTER names a file to run once the
// engine is up (used by the integration test).
var root = "SB_ROOT".getenv ?? { thisProcess.nowExecutingPath.dirname };
var s = Server.default;
var sb;
(root +/+ "src/load.scd").load;
sb = ~sb;
// under test: count function calls for the coverage report
if(~t.notNil and: { ~t[\instrument].notNil }) { ~t.instrument(sb) };
sb.configureServer(s);
s.waitForBoot({
	sb.defs.do { |f| f.value(s) };
	s.sync;
	sb.starters.do { |pair| pair[1].value(sb, s) };
	s.sync;
	"sc-bassist: ready".postln;
	if("SB_NOGUI".getenv.isNil) { { sb.buildUi }.defer };
	"SB_AFTER".getenv !? { |p| p.load };
}, onFailure: {
	"sc-bassist: the audio server did not boot (is PipeWire/JACK running?)".postln;
	1.exit;
});
