#!/usr/bin/env bash
# Route an application's audio (e.g. the browser playing YouTube) into
# sc-bassist's input, using PipeWire's pw-link. sc-bassist must be running.
#
#   scripts/route-app.sh firefox             app -> SuperCollider (you still hear the app directly)
#   scripts/route-app.sh firefox --through   also unlink the app from your speakers/headphones:
#                                            you hear it only through sc-bassist's mixer
#                                            (raise "source" in the Mixer section)
#   scripts/route-app.sh --list              list output ports to pick a pattern
#
# Other inputs linked to SuperCollider (e.g. the microphone) are unlinked.
# Undo --through by restarting playback in the app or with qpwgraph/helvum.
set -euo pipefail

if [[ "${1:-}" == --list || $# -eq 0 ]]; then
	pw-link -o | grep -v '^SuperCollider' || true
	[[ $# -eq 0 ]] && echo "usage: $0 <app-pattern> [--through] | --list" >&2
	exit 0
fi
pattern="$1"
through="${2:-}"

mapfile -t ports < <(pw-link -o | grep -i -- "$pattern" | grep -v '^SuperCollider' || true)
if [[ ${#ports[@]} -eq 0 ]]; then
	echo "no output ports match '$pattern' (is the app playing?); try --list" >&2
	exit 1
fi
left=""; right=""
for p in "${ports[@]}"; do
	case "$p" in
		*FL|*_1|*left*) [[ -z "$left" ]] && left="$p" ;;
		*FR|*_2|*right*) [[ -z "$right" ]] && right="$p" ;;
	esac
done
left="${left:-${ports[0]}}"
right="${right:-$left}"

# unlink whatever else feeds SuperCollider's inputs (pw-link -l prints
# each port followed by "  |<- source" lines for its incoming links)
while IFS=$'\t' read -r src dst; do
	pw-link -d "$src" "$dst" || true
done < <(pw-link -l | awk '
	/^SuperCollider:in_/ {port = $0; next}
	port != "" && /^ +\|<- / {sub(/^ +\|<- /, ""); print $0 "\t" port; next}
	{port = ""}')

linked=0
for pair in "$left|SuperCollider:in_1" "$right|SuperCollider:in_2"; do
	if pw-link "${pair%%|*}" "${pair#*|}"; then
		echo "linked ${pair%%|*} -> ${pair#*|}"
		linked=$((linked + 1))
	else
		echo "could not link ${pair%%|*} -> ${pair#*|} (already linked?)" >&2
	fi
done
if [[ $linked -eq 0 ]]; then exit 1; fi

if [[ "$through" == --through ]]; then
	for p in "$left" "$right"; do
		while IFS= read -r dst; do
			[[ -z "$dst" || "$dst" == SuperCollider:* ]] && continue
			pw-link -d "$p" "$dst" && echo "unlinked $p -> $dst"
		done < <(pw-link -l | awk -v src="$p" '
			$0 == src {on = 1; next}
			on && /^ +\|->/ {sub(/^ +\|-> /, ""); print; next}
			{on = 0}')
	done
	echo "now raise 'source' in the Mixer section: you hear the app through sc-bassist"
fi
