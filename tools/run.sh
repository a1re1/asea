#!/bin/bash
# Launch ASEA with an auto-detected Godot binary.
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
	echo "run.sh: no Godot binary found. Set GODOT=/path/to/Godot" >&2
	exit 2
fi
exec "$GODOT_BIN" --path "$ROOT" "$@"
