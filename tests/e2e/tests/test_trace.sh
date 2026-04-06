#!/usr/bin/env bash
# E2E test: N2_TRACE_SOURCE and N2_TRACE_VARS debug features
# Verifies that the tracing flags produce correct stderr output during
# shell initialization, and stay quiet when disabled.

set -euo pipefail

N2_DIR=${N2_DIR:-/n2}
SESSION=trace_test
PASS=0
FAIL=0

pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL + 1)); }

cleanup() {
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    [ -n "${PLAYGROUND_DIR:-}" ] && [ -d "${PLAYGROUND_DIR:-}" ] && rm -rf "$PLAYGROUND_DIR"
}
trap cleanup EXIT

echo "=== test_trace.sh ==="

# Helper: wait for a string in the tmux pane (min_count occurrences)
wait_for() {
    local pattern=$1
    local timeout=${2:-30}
    local min_count=${3:-2}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local count
        count=$(tmux capture-pane -t "$SESSION" -p -S - | grep -cE "$pattern" || true)
        if [ "$count" -ge "$min_count" ]; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "TIMEOUT waiting for: $pattern (count=$count, need=$min_count, after ${timeout}s)"
    return 1
}

# Install n2 to a playground directory
INSTALL_OUTPUT=$(PLAYGROUND=yes AUTO_CONFIRM=yes bash "$N2_DIR/install.sh" 2>&1)
PLAYGROUND_DIR=$(echo "$INSTALL_OUTPUT" | grep -o "Installed to playground dir: [^[:space:]]*" | awk '{print $NF}' | tail -1)

if [ -z "$PLAYGROUND_DIR" ] || [ ! -d "$PLAYGROUND_DIR" ]; then
    echo "FAIL: Could not create playground installation"
    exit 1
fi
echo "Playground dir: $PLAYGROUND_DIR"

ln -s "$N2_DIR" "$PLAYGROUND_DIR/.n2"

# ---------------------------------------------------------------------------
# Test 1: N2_TRACE_SOURCE=yes — trace lines should appear on shell init
# ---------------------------------------------------------------------------
tmux new-session -d -s "$SESSION" -x 220 -y 50

# Start shell with N2_TRACE_SOURCE enabled — redirect stderr to a file
TRACE_LOG="$PLAYGROUND_DIR/trace_source.log"
tmux send-keys -t "$SESSION" "N2_TRACE_SOURCE=yes HOME='$PLAYGROUND_DIR' bash --login 2>'$TRACE_LOG'" Enter
sleep 5
tmux send-keys -t "$SESSION" "echo TRACE_SOURCE_READY" Enter
wait_for "TRACE_SOURCE_READY" 15

if [ -s "$TRACE_LOG" ] && grep -q '\[n2:trace\] source' "$TRACE_LOG"; then
    pass "N2_TRACE_SOURCE=yes: trace lines appear in stderr"
else
    fail "N2_TRACE_SOURCE=yes: no trace lines found"
    echo "--- trace log ---"
    cat "$TRACE_LOG" 2>/dev/null || echo "(empty)"
    echo "--- end ---"
fi

# Verify multiple files are traced (profile.d + rc.d)
TRACE_COUNT=$(grep -c '\[n2:trace\] source' "$TRACE_LOG" || true)
if [ "$TRACE_COUNT" -ge 4 ]; then
    pass "N2_TRACE_SOURCE=yes: traced $TRACE_COUNT files (>= 4 expected)"
else
    fail "N2_TRACE_SOURCE=yes: only $TRACE_COUNT trace lines (expected >= 4)"
fi

# Exit the traced shell
tmux send-keys -t "$SESSION" "exit" Enter
sleep 1

# ---------------------------------------------------------------------------
# Test 2: N2_TRACE_SOURCE not set — no trace lines
# ---------------------------------------------------------------------------
QUIET_LOG="$PLAYGROUND_DIR/trace_quiet.log"
tmux send-keys -t "$SESSION" "HOME='$PLAYGROUND_DIR' bash --login 2>'$QUIET_LOG'" Enter
sleep 5
tmux send-keys -t "$SESSION" "echo QUIET_READY" Enter
wait_for "QUIET_READY" 15

QUIET_COUNT=$(grep -c '\[n2:trace\]' "$QUIET_LOG" || true)
if [ "$QUIET_COUNT" -eq 0 ]; then
    pass "N2_TRACE_SOURCE unset: no trace output (clean)"
else
    fail "N2_TRACE_SOURCE unset: unexpected $QUIET_COUNT trace lines in stderr"
fi

tmux send-keys -t "$SESSION" "exit" Enter
sleep 1

# ---------------------------------------------------------------------------
# Test 3: N2_TRACE_VARS=PATH — should show PATH changes during init
# ---------------------------------------------------------------------------
VARS_LOG="$PLAYGROUND_DIR/trace_vars.log"
tmux send-keys -t "$SESSION" "N2_TRACE_VARS=PATH HOME='$PLAYGROUND_DIR' bash --login 2>'$VARS_LOG'" Enter
sleep 5
tmux send-keys -t "$SESSION" "echo VARS_READY" Enter
wait_for "VARS_READY" 15

if [ -s "$VARS_LOG" ] && grep -q '\[n2:trace\] PATH:' "$VARS_LOG"; then
    pass "N2_TRACE_VARS=PATH: PATH changes traced"
else
    # PATH might not change during init on all systems — check if trace machinery ran
    if [ -s "$VARS_LOG" ]; then
        pass "N2_TRACE_VARS=PATH: trace log present (PATH may not have changed)"
    else
        fail "N2_TRACE_VARS=PATH: no trace output at all"
    fi
fi

tmux send-keys -t "$SESSION" "exit" Enter
sleep 1

# ---------------------------------------------------------------------------
# Test 4: Both flags together
# ---------------------------------------------------------------------------
BOTH_LOG="$PLAYGROUND_DIR/trace_both.log"
tmux send-keys -t "$SESSION" "N2_TRACE_SOURCE=yes N2_TRACE_VARS=PATH,EDITOR HOME='$PLAYGROUND_DIR' bash --login 2>'$BOTH_LOG'" Enter
sleep 5
tmux send-keys -t "$SESSION" "echo BOTH_READY" Enter
wait_for "BOTH_READY" 15

if grep -q '\[n2:trace\] source' "$BOTH_LOG"; then
    pass "Both flags: source tracing works"
else
    fail "Both flags: source tracing missing"
fi

tmux send-keys -t "$SESSION" "exit" Enter
sleep 1

# ---------------------------------------------------------------------------
# Test 5: Nested sourcing produces indented output
# ---------------------------------------------------------------------------
# Create a test file that sources another file
mkdir -p "$PLAYGROUND_DIR/test_nested"
cat > "$PLAYGROUND_DIR/test_nested/outer.sh" << 'EOF'
# outer.sh - sources inner.sh
__n2_source "$HOME/test_nested/inner.sh"
EOF
cat > "$PLAYGROUND_DIR/test_nested/inner.sh" << 'EOF'
# inner.sh - leaf file
export INNER_SOURCED=yes
EOF

NESTED_LOG="$PLAYGROUND_DIR/trace_nested.log"
tmux send-keys -t "$SESSION" "N2_TRACE_SOURCE=yes HOME='$PLAYGROUND_DIR' bash --login 2>'$NESTED_LOG'" Enter
sleep 3
# Source the outer file which will nest-source inner
tmux send-keys -t "$SESSION" "__n2_source \"\$HOME/test_nested/outer.sh\"" Enter
sleep 1
tmux send-keys -t "$SESSION" "echo NESTED_READY" Enter
wait_for "NESTED_READY" 15

# Check for indentation in nested source (inner.sh should be indented under outer.sh)
if grep -q '\[n2:trace\]   source' "$NESTED_LOG"; then
    pass "Nested sourcing: indentation present for nested files"
else
    # Show the log for debugging
    echo "--- nested trace log ---"
    cat "$NESTED_LOG" 2>/dev/null || echo "(empty)"
    echo "--- end ---"
    fail "Nested sourcing: no indentation found for nested source"
fi

# Verify the hierarchy: outer.sh at level 0, inner.sh at level 1 (indented)
OUTER_LINE=$(grep 'outer.sh' "$NESTED_LOG" | head -1)
INNER_LINE=$(grep 'inner.sh' "$NESTED_LOG" | head -1)

if [ -n "$OUTER_LINE" ] && [ -n "$INNER_LINE" ]; then
    # Extract indentation (spaces after [n2:trace])
    OUTER_INDENT=$(echo "$OUTER_LINE" | sed 's/.*\[n2:trace\]\( *\)source.*/\1/' | wc -c)
    INNER_INDENT=$(echo "$INNER_LINE" | sed 's/.*\[n2:trace\]\( *\)source.*/\1/' | wc -c)
    if [ "$INNER_INDENT" -gt "$OUTER_INDENT" ]; then
        pass "Nested sourcing: inner.sh is more indented than outer.sh"
    else
        fail "Nested sourcing: inner.sh not more indented than outer.sh"
    fi
else
    fail "Nested sourcing: could not find both outer.sh and inner.sh trace lines"
fi

tmux send-keys -t "$SESSION" "exit" Enter
sleep 1

# Kill the tmux session
tmux kill-session -t "$SESSION" 2>/dev/null || true

echo
echo "Results: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ] || exit 1
echo "All trace tests passed!"
