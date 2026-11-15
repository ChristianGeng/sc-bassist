#!/usr/bin/env bash
# Start sc-bassist.
#   ./run.sh                 demo groove (no setup needed)
#   ./run.sh --live          listen to the audio input (route YouTube with scripts/route-app.sh)
#   ./run.sh --file song.mp3 play along with a file
#   ./run.sh --nogui         engine only, control it over OSC
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/sc-env.sh
source "$ROOT/scripts/sc-env.sh"

usage() { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
	case "$1" in
		--live) export SB_SOURCE=live; shift ;;
		--file)
			[[ $# -ge 2 ]] || { echo "--file needs a path" >&2; usage >&2; exit 2; }
			SB_FILE="$(realpath "$2")"; export SB_FILE; shift 2 ;;
		--nogui) export SB_NOGUI=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
	esac
done

export SB_ROOT="$ROOT" SB_EXIT_ON_CLOSE=1
cd "$ROOT"
exec "${SCLANG[@]}" "$ROOT/main.scd"
