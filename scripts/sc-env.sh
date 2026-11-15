# shellcheck shell=bash
# Sourced by run.sh and test.sh: finds SuperCollider and sets SCLANG.
#
# Prefers the no-root install in $SC_PREFIX (scripts/install-local-sc.sh),
# falls back to a system sclang. On PipeWire, PipeWire's libjack goes
# first on the library path, so scsynth talks to PipeWire (same effect
# as pw-jack, which cannot be combined with our own LD_LIBRARY_PATH).

# shellcheck disable=SC2034 # SCLANG is used by the scripts that source this
SC_PREFIX="${SC_PREFIX:-$HOME/.local/opt/supercollider}"
PW_JACK_DIR=""
for d in /usr/lib/*/pipewire-0.3/jack /usr/lib/pipewire-0.3/jack; do
	if [[ -e "$d/libjack.so.0" ]]; then PW_JACK_DIR="$d"; break; fi
done
if [[ "${SB_NO_PWJACK:-}" == 1 ]]; then PW_JACK_DIR=""; fi

if [[ -x "$SC_PREFIX/usr/bin/sclang" ]]; then
	sc_libs="$SC_PREFIX/usr/lib"
	for d in "$SC_PREFIX"/usr/lib/*-linux-gnu; do
		if [[ -d "$d" ]]; then sc_libs="$sc_libs:$d"; fi
	done
	export LD_LIBRARY_PATH="${PW_JACK_DIR:+$PW_JACK_DIR:}$sc_libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	export SB_SCSYNTH="$SC_PREFIX/usr/bin/scsynth"
	export SB_PLUGINS="$SC_PREFIX/usr/lib/SuperCollider/plugins"
	SCLANG=("$SC_PREFIX/usr/bin/sclang" -l "$SC_PREFIX/sclang_conf.yaml")
elif command -v sclang >/dev/null 2>&1; then
	if [[ -n "$PW_JACK_DIR" ]]; then
		export LD_LIBRARY_PATH="$PW_JACK_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	fi
	SCLANG=(sclang)
else
	echo "SuperCollider not found. Run scripts/install-local-sc.sh (no root)" >&2
	echo "or install it system-wide: sudo apt install supercollider" >&2
	exit 1
fi
# SCLANG is an array: callers source this file, it cannot be exported
