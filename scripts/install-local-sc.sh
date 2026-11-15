#!/usr/bin/env bash
# Install SuperCollider without root into $SC_PREFIX (default
# ~/.local/opt/supercollider) by unpacking the distribution's packages.
#
# Why not `apt install supercollider`: on a PipeWire system it replaces
# libjack0 (used by mpv, OBS, gstreamer, portaudio) with jackd2's
# library and installs a JACK server, i.e. it changes the audio stack.
# Unpacking leaves the system untouched; run.sh then uses PipeWire's
# JACK library. Needs apt-get (Debian/Ubuntu) but no sudo.
set -euo pipefail
SC_PREFIX="${SC_PREFIX:-$HOME/.local/opt/supercollider}"
PKGS=(supercollider-language supercollider-server supercollider-common libscsynth1
	libqt5webenginewidgets5 libzita-alsa-pcmi0 libzita-resampler1)

if [[ -x "$SC_PREFIX/usr/bin/sclang" && "${1:-}" != --force ]]; then
	echo "SuperCollider already in $SC_PREFIX (use --force to reinstall)"
	exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
(cd "$work" && apt-get download "${PKGS[@]}")
mkdir -p "$SC_PREFIX"
for deb in "$work"/*.deb; do dpkg -x "$deb" "$SC_PREFIX"; done

cat >"$SC_PREFIX/sclang_conf.yaml" <<EOF
includePaths:
  - $SC_PREFIX/usr/share/SuperCollider/SCClassLibrary
excludePaths: []
postInlineWarnings: false
excludeDefaultPaths: true
EOF

libs="$SC_PREFIX/usr/lib"
for d in "$SC_PREFIX"/usr/lib/*-linux-gnu; do libs="$libs:$d"; done
missing="$(LD_LIBRARY_PATH="$libs" ldd "$SC_PREFIX/usr/bin/sclang" "$SC_PREFIX/usr/bin/scsynth" \
	| awk '/not found/ {print $1}' | sort -u || true)"
if [[ -n "$missing" ]]; then
	echo "Installed, but these libraries are missing on this system:" >&2
	echo "$missing" >&2
	echo "Install the packages that provide them (apt-file search <lib>)." >&2
	exit 1
fi
echo "SuperCollider $(dpkg-deb -f "$work"/supercollider-language_*.deb Version) installed in $SC_PREFIX"
