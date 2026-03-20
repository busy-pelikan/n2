#!/usr/bin/env bash
# E2E test: git indicator in PS1 prompt
# Installs n2 into a PLAYGROUND home directory, opens a bash login shell with
# that home, initializes a git repo, and verifies that:
#   - The prompt shows reponame[branch] when inside a git repo
#   - The branch name updates when switching branches

set -euo pipefail

N2_DIR=${N2_DIR:-/n2}
SESSION=n2_git_prompt_test
PASS=0
FAIL=0

pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL + 1)); }

cleanup() {
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    [ -n "${PLAYGROUND_DIR:-}" ] && [ -d "${PLAYGROUND_DIR:-}" ] && rm -rf "$PLAYGROUND_DIR"
}
trap cleanup EXIT

echo "=== test_git_prompt.sh ==="

# Helper: wait for a string to appear in tmux pane output (not just the input line).
# When we send "cmd; echo MARKER", MARKER appears once in the typed command.
# After the command finishes, MARKER appears again as actual output.
# Waiting for >=2 occurrences ensures the command has actually run.
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
# Setup: create a test git repo named "mytestrepo" inside the playground
# ---------------------------------------------------------------------------
REPO_DIR="$PLAYGROUND_DIR/mytestrepo"
tmux send-keys -t "$SESSION" "mkdir -p '$REPO_DIR' && cd '$REPO_DIR' && git init && git checkout -b main 2>/dev/null || true && echo GIT_INIT_DONE" Enter
wait_for "GIT_INIT_DONE" 15

# Configure git user identity so commits work (containers often lack this)
tmux send-keys -t "$SESSION" "git config user.email 'test@example.com' && git config user.name 'Test' && echo GIT_CONFIG_DONE" Enter
wait_for "GIT_CONFIG_DONE" 10

# Create an initial commit so the branch truly exists
tmux send-keys -t "$SESSION" "touch README && git add README && git commit -m init && echo GIT_COMMIT_DONE" Enter
wait_for "GIT_COMMIT_DONE" 15

# Force a prompt re-render by running a no-op
tmux send-keys -t "$SESSION" "echo IN_REPO_PROMPT_CHECK" Enter
wait_for "IN_REPO_PROMPT_CHECK" 10
sleep 2

OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -)
echo "--- prompt inside git repo ---"
echo "$OUTPUT"
echo "--- end prompt inside git repo ---"

# ---------------------------------------------------------------------------
# Test 1: Prompt shows "mytestrepo[main]" (or truncated variant)
# The git indicator format is: reponame[branchname]
# "mytestrepo" is 10 chars (≤12) so no truncation.
# ---------------------------------------------------------------------------
if echo "$OUTPUT" | grep -qE 'mytestrepo\[main\]'; then
    pass "Git prompt: 'mytestrepo[main]' appears in prompt"
else
    fail "Git prompt: 'mytestrepo[main]' not found in prompt"
fi

# ---------------------------------------------------------------------------
# Test 2: Create and switch to a new branch, verify branch name updates
# ---------------------------------------------------------------------------
tmux send-keys -t "$SESSION" "git checkout -b feat/test-branch && echo GIT_BRANCH_DONE" Enter
wait_for "GIT_BRANCH_DONE" 15
sleep 2

# Force prompt re-render
tmux send-keys -t "$SESSION" "echo IN_NEW_BRANCH_PROMPT_CHECK" Enter
wait_for "IN_NEW_BRANCH_PROMPT_CHECK" 10
sleep 2

OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -)
echo "--- prompt on new branch ---"
echo "$OUTPUT"
echo "--- end prompt on new branch ---"

if echo "$OUTPUT" | grep -qE 'mytestrepo\[feat/test-branch\]'; then
    pass "Git prompt: branch name updates to 'feat/test-branch'"
else
    fail "Git prompt: 'mytestrepo[feat/test-branch]' not found after branch switch"
fi

# ---------------------------------------------------------------------------
# Test 3: Outside a git repo, the git indicator should not appear
# ---------------------------------------------------------------------------
tmux send-keys -t "$SESSION" "cd /tmp && echo OUTSIDE_REPO_DONE" Enter
wait_for "OUTSIDE_REPO_DONE" 10
sleep 2

# Force prompt re-render
tmux send-keys -t "$SESSION" "echo OUTSIDE_REPO_PROMPT_CHECK" Enter
wait_for "OUTSIDE_REPO_PROMPT_CHECK" 10
sleep 2

OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -)
echo "--- prompt outside git repo ---"
echo "$OUTPUT"
echo "--- end prompt outside git repo ---"

# After the OUTSIDE_REPO_PROMPT_CHECK line, the next prompt should not contain
# "mytestrepo[" since we're in /tmp (not a git repo).
# The n2 git indicator format is: reponame[branchname]
# We specifically check that no word[word] pattern appears in the prompt lines
# (excluding verbose trace lines like "[1] -> ..." which start with [digit]).
AFTER_OUTPUT=$(echo "$OUTPUT" | grep -A 20 "OUTSIDE_REPO_PROMPT_CHECK" | tail -n +2)
# Match the specific n2 git indicator format: word[word] (e.g. mytestrepo[main])
if echo "$AFTER_OUTPUT" | grep -qE '[a-zA-Z0-9_.-]+\[[a-zA-Z0-9_/.-]+\]'; then
    fail "Git prompt: git indicator still appears outside git repo"
else
    pass "Git prompt: no git indicator when outside a git repo"
fi

echo
echo "Results: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ] || exit 1
echo "All git prompt tests passed!"
