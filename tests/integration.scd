// Integration test: boots the real engine headless with the demo groove
// as input (known ground truth: 104 BPM, chords Am F C G) and checks
// that analysis, the bassist, the effects, OSC control and file input
// work end to end. Ports are not connected, so nothing is audible.
var root = "SB_ROOT".getenv;
(root +/+ "tests/harness.scd").load;
"SB_NOGUI".setenv("1");
"SB_AFTER".setenv(root +/+ "tests/integration_body.scd");
(root +/+ "main.scd").load;
// safety net if the server never comes up
AppClock.sched(110, { "integration: timeout".postln; 1.exit; nil });
