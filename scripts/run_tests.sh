#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOG_DIR="$ROOT_DIR/tests/logs"
mkdir -p "$LOG_DIR"

STAMP="$(date +"%Y%m%d_%H%M%S")"
RUN_LOG="$LOG_DIR/run_${STAMP}.log"
SYNTAX_LOG="$LOG_DIR/syntax_${STAMP}.log"

echo "ChordNotebook test run: $STAMP" | tee -a "$RUN_LOG"
echo "Root: $ROOT_DIR" | tee -a "$RUN_LOG"

find_lua_bin() {
	for bin in lua lua5.4 lua5.3 luajit; do
		if command -v "$bin" >/dev/null 2>&1; then
			echo "$bin"
			return 0
		fi
	done
	return 1
}

LUA_BIN="$(find_lua_bin || true)"
if [ -z "$LUA_BIN" ]; then
	echo "ERROR: Lua interpreter not found (tried: lua, lua5.4, lua5.3, luajit)." | tee -a "$RUN_LOG"
	exit 1
fi

echo "Lua: $LUA_BIN" | tee -a "$RUN_LOG"

echo "Running syntax checks (luac -p)..." | tee -a "$RUN_LOG"
: >"$SYNTAX_LOG"
SYNTAX_FAILED=0

list_lua_files() {
	if command -v rg >/dev/null 2>&1; then
		(cd "$ROOT_DIR" && rg --files -g '*.lua' | sort)
	else
		(cd "$ROOT_DIR" && find . -name '*.lua' -type f | sed 's#^\./##' | sort)
	fi
}

while IFS= read -r file; do
	if ! luac -p "$file" >>"$SYNTAX_LOG" 2>&1; then
		SYNTAX_FAILED=1
		echo "Syntax FAIL: $file" | tee -a "$RUN_LOG"
	fi
done <<EOF
$(list_lua_files)
EOF

if [ "$SYNTAX_FAILED" -ne 0 ]; then
	echo "Syntax checks failed. See: $SYNTAX_LOG" | tee -a "$RUN_LOG"
	exit 1
fi

echo "Syntax checks passed." | tee -a "$RUN_LOG"

echo "Running unit/integration script: tests/test_runner.lua" | tee -a "$RUN_LOG"
if ! (cd "$ROOT_DIR" && "$LUA_BIN" tests/test_runner.lua) >>"$RUN_LOG" 2>&1; then
	echo "Test runner failed. See: $RUN_LOG" | tee -a "$RUN_LOG"
	exit 1
fi

echo "All tests passed. Logs:" | tee -a "$RUN_LOG"
echo "- $RUN_LOG" | tee -a "$RUN_LOG"
echo "- $SYNTAX_LOG" | tee -a "$RUN_LOG"
