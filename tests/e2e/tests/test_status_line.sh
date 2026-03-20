#!/usr/bin/env bash
# E2E test: status line and command expansion features
# Installs n2 into a PLAYGROUND home directory, opens a bash login shell with
# that home, and verifies that:
#   - The command expansion line "[N] ->" appears after running a command
#   - "Status OK" appears after a successful command
#   - "Error" appears after a failing command
#   - The timestamp format (HH:MM:SS Mon DD) is present in the status line

set -euo pipefail

N2_DIR=${N2_DIR:-/n2}
SESSION=n2_status_line_test
PASS=0
FAIL=0

pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL + 1)); }

cleanup() {
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    [ -n "${PLAYGROUND_DIR:-}" ] && [ -d "${PLAYGROUND_DIR:-}" ] && rm -rf "$PLAYGROUND_DIR"
}
trap cleanup EXIT

echo "=== test_status_line.sh ==="

# Helper: wait for a string to appear in the tmux pane
wait_for() {
    local pattern=$1
    local timeout=${2:-30}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if tmux capture-pane -t "$SESSION" -p -S - | grep -qE "$pattern"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "TIMEOUT waiting for: $pattern (after ${timeout}s)"
    return 1
}

# Install n2 to a playground directory (non-interactive)
INSTALL_OUTPUT=$(PLAYGROUND=yes AUTO_CONFIRM=yes bash "$N2_DIR/install.sh" 2>&1)
echo "--- install output ---"
echo "$INSTALL_OUTPUT"
echo "--- end install output ---"

PLAYGROUND_DIR=$(echo "$INSTALL_OUTPUT" | grep -o "Installed to playground dir: [^[:space:]]*" | awk '{print $NF}' | tail -1)

if [ -z "$PLAYGROUND_DIR" ] || [ ! -d "$PLAYGROUND_DIR" ]; then
    echo "FAIL: Could not create playground installation (got: '$PLAYGROUND_DIR')"
    exit 1
fi
echo "Playground dir: $PLAYGROUND_DIR"

# Start a detached tmux session
tmux new-session -d -s "$SESSION" -x 220 -y 50

# Open a bash login shell using the playground home directory
tmux send-keys -t "$SESSION" "HOME='$PLAYGROUND_DIR' bash --login" Enter

# Wait for the shell to be ready
sleep 5
tmux send-keys -t "$SESSION" "echo N2_SHELL_READY" Enter
wait_for "N2_SHELL_READY" 15

# ---------------------------------------------------------------------------
# Test 1: Command expansion line — run "echo hello", expect "[1] ->"
# The command expansion is printed to stderr before the command runs.
# ---------------------------------------------------------------------------
tmux send-keys -t "$SESSION" "echo hello" Enter
sleep 2

OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -)
echo "--- echo hello output ---"
echo "$OUTPUT"
echo "--- end echo hello output ---"

# The cmd expansion format is: [N] -> /path/to/echo hello (HH:MM:SS Mon DD)
if echo "$OUTPUT" | grep -qE '\[1\] ->'; then
    pass "Command expansion: '[1] ->' appears after running echo"
else
    fail "Command expansion: '[1] ->' not found"
fi

# ---------------------------------------------------------------------------
# Test 2: "Status OK" appears after successful command
# ---------------------------------------------------------------------------
if echo "$OUTPUT" | grep -q "Status OK"; then
    pass "Status line: 'Status OK' appears after successful command"
else
    fail "Status line: 'Status OK' not found after echo hello"
fi

# ---------------------------------------------------------------------------
# Test 3: Timestamp format in status line — e.g. "10:45:30 Mar 19"
# Format: HH:MM:SS Mon DD (24-hour, 3-letter month, 1-2 digit day)
# ---------------------------------------------------------------------------
if echo "$OUTPUT" | grep -qE '[0-9]{2}:[0-9]{2}:[0-9]{2} [A-Z][a-z]{2} [0-9]{1,2}'; then
    pass "Status line: timestamp format HH:MM:SS Mon DD present"
else
    fail "Status line: timestamp not found in expected format"
fi

# ---------------------------------------------------------------------------
# Test 4: Duration field present — e.g. "0s" or "1s" or "1m30s"
# ---------------------------------------------------------------------------
if echo "$OUTPUT" | grep -qE '[0-9]+(h|m|s)'; then
    pass "Status line: duration field present"
else
    fail "Status line: duration field not found"
fi

# ---------------------------------------------------------------------------
# Test 5: Failing command produces "Error" in the status line
# ---------------------------------------------------------------------------
tmux send-keys -t "$SESSION" "false" Enter
sleep 2
wait_for "Error" 10

OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -)
echo "--- false command output ---"
echo "$OUTPUT"
echo "--- end false command output ---"

if echo "$OUTPUT" | grep -qE "Error [0-9]+"; then
    pass "Status line: 'Error N' appears after failing command (false)"
else
    fail "Status line: 'Error N' not found after false"
fi

# ---------------------------------------------------------------------------
# Test 6: Shell is still usable after a failing command
# ---------------------------------------------------------------------------
tmux send-keys -t "$SESSION" "echo AFTER_FAIL" Enter
wait_for "AFTER_FAIL" 10

if tmux capture-pane -t "$SESSION" -p -S - | grep -q "AFTER_FAIL"; then
    pass "Shell remains functional after failing command"
else
    fail "Shell not responsive after failing command"
fi

echo
echo "Results: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ] || exit 1
echo "All status line tests passed!"
