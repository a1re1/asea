#!/bin/bash
# ASEA verification: headless import + logic tests + runtime_smoke.
# Callable from any cwd. One aggregate DRIP_VERIFY from real stage counts.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

detect_godot() {
	if [ -n "${GODOT:-}" ] && [ -x "$GODOT" ]; then
		printf '%s\n' "$GODOT"
		return 0
	fi
	for candidate in \
		"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" \
		"/Applications/Godot.app/Contents/MacOS/Godot"; do
		if [ -x "$candidate" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	local cmd path
	for cmd in godot godot4; do
		path="$(command -v "$cmd" 2>/dev/null || true)"
		if [ -n "$path" ] && [ -x "$path" ]; then
			printf '%s\n' "$path"
			return 0
		fi
	done
	return 1
}

GODOT_BIN="$(detect_godot || true)"
if [ -z "$GODOT_BIN" ]; then
	echo "verify.sh: no Godot binary found. Set GODOT=/path/to/Godot" >&2
	exit 2
fi

LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/asea-verify.XXXXXX")"
LOG="$LOGDIR/stage.log"
STATUS=0
LOGIC_EXEC=0
LOGIC_PASS=0
LOGIC_FAIL=0
SMOKE_EXEC=0
SMOKE_PASS=0
SMOKE_FAIL=0
HAVE_LOGIC_DRIP=0
HAVE_SMOKE_DRIP=0

cleanup() {
	rm -rf "$LOGDIR"
}
trap cleanup EXIT

run_with_timeout() {
	local secs="$1"
	shift
	"$@" &
	local pid=$!
	local i=0
	while kill -0 "$pid" 2>/dev/null; do
		i=$((i + 1))
		if [ "$i" -ge "$secs" ]; then
			echo "verify.sh: watchdog killed PID $pid after ${secs}s" >&2
			kill -TERM "$pid" 2>/dev/null || true
			sleep 1
			kill -KILL "$pid" 2>/dev/null || true
			wait "$pid" 2>/dev/null || true
			return 124
		fi
		sleep 1
	done
	wait "$pid"
	return $?
}

anchored_engine_errors() {
	grep -E '^[[:space:]]*(SCRIPT ERROR:|SHADER ERROR:|ERROR:|Parse Error:)' "$LOG" || true
}

parse_drip_line() {
	grep -E '^DRIP_VERIFY \{.*\}$' "$LOG" | tail -1 || true
}

parse_int_field() {
	local line="$1" field="$2"
	printf '%s\n' "$line" | sed -n "s/.*\"${field}\":[[:space:]]*\([0-9][0-9]*\).*/\1/p" | tail -1
}

stage_engine_or_status_failed() {
	local status="$1"
	local errs
	errs="$(anchored_engine_errors)"
	if [ -n "$errs" ]; then
		echo "verify.sh: stage emitted anchored engine errors:" >&2
		printf '%s\n' "$errs" | head -20 >&2
		return 0
	fi
	if [ "$status" -ne 0 ]; then
		echo "verify.sh: stage exited with status $status" >&2
		tail -40 "$LOG" >&2
		return 0
	fi
	return 1
}

require_drip() {
	local label="$1"
	local line execn passn failn
	line="$(parse_drip_line)"
	if [ -z "$line" ]; then
		echo "verify.sh: $label missing nonempty DRIP_VERIFY record" >&2
		tail -40 "$LOG" >&2
		return 1
	fi
	execn="$(parse_int_field "$line" executed)"
	passn="$(parse_int_field "$line" passed)"
	failn="$(parse_int_field "$line" failed)"
	execn="${execn:-0}"
	passn="${passn:-0}"
	failn="${failn:-0}"
	echo "verify.sh: $label assertions executed=$execn passed=$passn failed=$failn"
	if [ "$label" = "logic tests" ]; then
		LOGIC_EXEC="$execn"
		LOGIC_PASS="$passn"
		LOGIC_FAIL="$failn"
		HAVE_LOGIC_DRIP=1
	elif [ "$label" = "runtime smoke" ]; then
		SMOKE_EXEC="$execn"
		SMOKE_PASS="$passn"
		SMOKE_FAIL="$failn"
		HAVE_SMOKE_DRIP=1
	fi
	if [ "$execn" -le 0 ]; then
		echo "verify.sh: $label DRIP_VERIFY executed must be > 0" >&2
		return 1
	fi
	if [ "$failn" -ne 0 ] || [ "$passn" -ne "$execn" ]; then
		echo "verify.sh: $label assertion counts not clean (passed=executed, failed=0)" >&2
		return 1
	fi
	return 0
}

emit_aggregate() {
	local execn passn failn
	execn=$((LOGIC_EXEC + SMOKE_EXEC))
	passn=$((LOGIC_PASS + SMOKE_PASS))
	failn=$((LOGIC_FAIL + SMOKE_FAIL))
	# Report only assertions that actually ran. Missing stages and engine
	# errors still fail the command through fail_now's nonzero exit status.
	printf 'DRIP_VERIFY {"executed":%s,"passed":%s,"failed":%s}\n' "$execn" "$passn" "$failn"
}

fail_now() {
	STATUS=1
	emit_aggregate
	exit 1
}

run_stage() {
	local label="$1"
	local timeout_s="$2"
	shift 2
	echo "verify.sh: stage: $label"
	: >"$LOG"
	run_with_timeout "$timeout_s" "$@" >"$LOG" 2>&1
	local status=$?
	if stage_engine_or_status_failed "$status"; then
		echo "verify.sh: FAILED at stage: $label" >&2
		# Still harvest a DRIP_VERIFY if the stage printed one.
		if [ "$label" = "logic tests" ] || [ "$label" = "runtime smoke" ]; then
			require_drip "$label" || true
		fi
		fail_now
	fi
	if [ "$label" = "logic tests" ] || [ "$label" = "runtime smoke" ]; then
		if ! require_drip "$label"; then
			echo "verify.sh: FAILED at stage: $label (DRIP_VERIFY)" >&2
			fail_now
		fi
	fi
	echo "verify.sh: stage ok: $label"
}

# 1. Headless import (first run generates .godot/ caches).
run_stage "headless import" 180 "$GODOT_BIN" --headless --path "$ROOT" --editor --import

# 2. Logic suite (must emit nonempty DRIP_VERIFY).
run_stage "logic tests" 180 "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/run_tests.gd

# 3. Dedicated runtime smoke: isolated save, fixed 60 fps, watchdog-bounded.
run_stage "runtime smoke" 90 "$GODOT_BIN" --headless --path "$ROOT" --fixed-fps 60 --script res://tests/runtime_smoke.gd -- --asea-smoke

emit_aggregate
echo "verify.sh: ALL STAGES PASSED"
exit 0
