// Loads all modules into ~sb in dependency order. Needs no server:
// the tests load this file and call the pure parts directly.
var dir = thisProcess.nowExecutingPath.dirname;
~sb = ();
~sb.root = dir.dirname;
["core", "theory", "sources", "analysis", "voice", "drone", "player", "fx", "remote", "ui"]
.do { |name| (dir +/+ name ++ ".scd").load };
