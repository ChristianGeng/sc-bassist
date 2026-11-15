#!/usr/bin/env bash
# Run test suites: scripts/test.sh [compile] [unit] [ui] [integration]
# (default: all). Headless: Qt renders offscreen, scsynth does not
# connect to any hardware port, so nothing is heard.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/sc-env.sh
source "$ROOT/scripts/sc-env.sh"
export SB_ROOT="$ROOT" QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
# tests are silent: the engine mixes to a private bus (SB_SILENT); the
# JACK variables additionally ask scsynth not to link any ports
export SB_SILENT=1
export SC_JACK_DEFAULT_INPUTS="sb-test-none" SC_JACK_DEFAULT_OUTPUTS="sb-test-none"
OUT="${SB_TEST_OUT:-$ROOT/out}"
mkdir -p "$OUT"
export SB_TEST_OUT="$OUT"

suites=("$@")
[[ ${#suites[@]} -eq 0 ]] && suites=(compile unit ui integration)

run_sclang() { # name file timeout
	local name="$1" file="$2" limit="$3" code=0
	echo "=== $name"
	timeout "$limit" "${SCLANG[@]}" "$file" >"$OUT/$name.log" 2>&1 || code=$?
	# an error before ~t.finish must not count as a pass
	if [[ $code -eq 0 ]] && ! grep -q "^$name: [0-9]* passed, 0 failed" "$OUT/$name.log"; then
		echo "--- $name: no summary line, the suite did not finish"
		code=1
	fi
	# sclang's own noise is in the log; show test lines and errors
	grep -E '^(FAIL|ERROR|ok |  - |unit:|ui:|integration:|compile:)|ERROR:|WARNING: sb' "$OUT/$name.log" || true
	if [[ $code -ne 0 ]]; then
		echo "--- $name failed (exit $code), last log lines:"
		tail -40 "$OUT/$name.log"
		return 1
	fi
}

status=0
# CI runs one suite per step: SB_COVERAGE_KEEP=1 merges over the steps
if [[ "${SB_COVERAGE_KEEP:-}" != 1 ]]; then rm -f "$OUT"/coverage-*.txt; fi
for s in "${suites[@]}"; do
	case "$s" in
		compile) run_sclang compile "$ROOT/tests/compile.scd" 60 || status=1 ;;
		unit) run_sclang unit "$ROOT/tests/unit.scd" 60 || status=1 ;;
		ui) run_sclang ui "$ROOT/tests/ui.scd" 60 || status=1 ;;
		integration) run_sclang integration "$ROOT/tests/integration.scd" 120 || status=1 ;;
		*) echo "unknown suite $s" >&2; status=2 ;;
	esac
done

# function coverage merged over the suites that ran (see tests/harness.scd)
if compgen -G "$OUT/coverage-*.txt" >/dev/null; then
	awk '{ n[$1] += $2 } END {
		for (f in n) { total++; if (n[f] > 0) hit++; else miss = miss "\n  " f }
		printf "=== function coverage: %d/%d (%.0f%%)\n", hit, total, 100 * hit / total
		if (miss != "") print "not called:" miss
	}' "$OUT"/coverage-*.txt | tee "$OUT/coverage.txt"
fi
exit $status
