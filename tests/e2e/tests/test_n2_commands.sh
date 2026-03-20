#!/usr/bin/env bash
# E2E test: n2 and m2 CLI commands after playground install
# Installs n2 into a PLAYGROUND home directory, opens a bash login shell with
# that home, and verifies that n2 status, n2 create-m2, m2 list, and m2 create
# behave correctly.

set -euo pipefail

N2_DIR=${N2_DIR:-/n2}
SESSION=n2_commands_test
PASS=0
FAIL=0

pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL + 1)); }

cleanup() {
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    [ -n "${PLAYGROUND_DIR:-}" ] && [ -d "${PLAYGROUND_DIR:-}" ] && rm -rf "$PLAYGROUND_DIR"
}
trap cleanup EXIT

echo "=== test_n2_commands.sh ==="

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
# Test 1: n2 status — should print git repo info with "Checking" and branch info
# ---------------------------------------------------------------------------
tmux send-keys -t "$SESSION" "n2 status; echo N2_STATUS_DONE" Enter
wait_for "N2_STATUS_DONE" 30

OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -)
echo "--- n2 status output ---"
echo "$OUTPUT"
echo "--- end n2 status output ---"

if echo "$OUTPUT" | grep -qiE "Checking"; then
    pass "n2 status: 'Checking' header appears"
else
    fail "n2 status: 'Checking' header not found"
fi

# n2 status runs git status on ~/.n2 (symlinked from N2_DIR)
# Look for a known git output pattern: branch, nothing to commit, or similar
if echo "$OUTPUT" | grep -qiE "(branch|nothing to commit|working tree|HEAD)"; then
    pass "n2 status: git repository info present"
else
    fail "n2 status: git repository info not found"
fi

# ---------------------------------------------------------------------------
# Test 2: n2 create-m2 — should create ~/.m2-00-demo
# ---------------------------------------------------------------------------
tmux send-keys -t "$SESSION" "n2 create-m2; echo N2_CREATE_M2_DONE" Enter
wait_for "N2_CREATE_M2_DONE" 30

OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -)
echo "--- n2 create-m2 output ---"
echo "$OUTPUT"
echo "--- end n2 create-m2 output ---"

if [ -d "$PLAYGROUND_DIR/.m2-00-demo" ]; then
    pass "n2 create-m2: ~/.m2-00-demo directory created"
else
    fail "n2 create-m2: ~/.m2-00-demo directory not found"
fi

if echo "$OUTPUT" | grep -qiE "(demo|m2-00-demo|Creating)"; then
    pass "n2 create-m2: creation message appeared"
else
    fail "n2 create-m2: creation message not found"
fi

# ---------------------------------------------------------------------------
# Test 3: m2 list — should list the created m2 directory
# ---------------------------------------------------------------------------
tmux send-keys -t "$SESSION" "m2 list; echo M2_LIST_DONE" Enter
wait_for "M2_LIST_DONE" 15

OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -)
echo "--- m2 list output ---"
echo "$OUTPUT"
echo "--- end m2 list output ---"

if echo "$OUTPUT" | grep -qE "m2-00-demo"; then
    pass "m2 list: shows .m2-00-demo directory"
else
    fail "m2 list: .m2-00-demo not found in output"
fi

# ---------------------------------------------------------------------------
# Test 4: m2 create (or n2 create-m2) should fail gracefully when demo exists
# ---------------------------------------------------------------------------
tmux send-keys -t "$SESSION" "n2 create-m2; echo N2_CREATE_M2_REPEAT_DONE" Enter
wait_for "N2_CREATE_M2_REPEAT_DONE" 15

OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -)
echo "--- n2 create-m2 repeat output ---"
echo "$OUTPUT"
echo "--- end n2 create-m2 repeat output ---"

# Should print an error / "Already exists" and not crash the shell
if echo "$OUTPUT" | grep -qiE "(already exists|Giving up|exists)"; then
    pass "n2 create-m2 (repeat): graceful failure message shown"
else
    fail "n2 create-m2 (repeat): expected 'Already exists' or similar message"
fi

# Shell should still be alive after the failure
tmux send-keys -t "$SESSION" "echo SHELL_STILL_ALIVE" Enter
wait_for "SHELL_STILL_ALIVE" 10
if tmux capture-pane -t "$SESSION" -p -S - | grep -q "SHELL_STILL_ALIVE"; then
    pass "Shell remains alive after failed n2 create-m2"
else
    fail "Shell did not respond after failed n2 create-m2"
fi

echo
echo "Results: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ] || exit 1
echo "All n2 command tests passed!"
