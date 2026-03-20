#!/usr/bin/env bash
# E2E test runner for n2
# Usage: ./tests/e2e/run.sh [--platform debian|fedora|macos] [--test install|prompt]
#
# Runs E2E tests inside Docker containers using tmux for terminal interaction.
# For macos, tests run natively (no Docker) with a temp HOME for isolation.
# Default: runs all tests on all platforms (debian/fedora only).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N2_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PLATFORMS=(debian fedora)
TESTS=(test_install test_prompt test_uninstall test_n2_commands test_git_prompt test_status_line)
PASS_TOTAL=0
FAIL_TOTAL=0
RESULTS=()

usage() {
    echo "Usage: $0 [--platform debian|fedora|macos] [--test install|prompt|uninstall]"
    echo ""
    echo "Options:"
    echo "  --platform, -p    Platform to test (can be repeated). Default: all"
    echo "  --test, -t        Test to run (install|prompt|uninstall, can be repeated). Default: all"
    echo "  --help, -h        Show this help"
    exit 0
}

# Parse args
SELECTED_PLATFORMS=()
SELECTED_TESTS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform|-p) SELECTED_PLATFORMS+=("$2"); shift 2 ;;
        --test|-t)     SELECTED_TESTS+=("test_$2"); shift 2 ;;
        --help|-h)     usage ;;
        *)             echo "Unknown option: $1"; usage ;;
    esac
done

[[ ${#SELECTED_PLATFORMS[@]} -eq 0 ]] && SELECTED_PLATFORMS=("${PLATFORMS[@]}")
[[ ${#SELECTED_TESTS[@]} -eq 0 ]]     && SELECTED_TESTS=("${TESTS[@]}")

# Check Docker is available (only needed for non-macos platforms)
need_docker=0
for p in "${SELECTED_PLATFORMS[@]}"; do
    [[ "$p" != "macos" ]] && need_docker=1
done
if [[ $need_docker -eq 1 ]] && ! command -v docker &>/dev/null; then
    echo "ERROR: docker is required but not found in PATH"
    exit 1
fi

run_test_macos() {
    local test_name=$2
    local label="macos/${test_name}"
    local test_script="$N2_ROOT/tests/e2e/tests/${test_name}.sh"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🍎 $label"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local tmp_home
    tmp_home="$(mktemp -d)"

    # Ensure brew-installed bash (4+) is first in PATH on macOS.
    # Stock macOS bash is 3.2 which is too old for n2's install.sh.
    local macos_path="$PATH"
    if [[ -x /opt/homebrew/bin/bash ]]; then
        macos_path="/opt/homebrew/bin:$macos_path"
    elif [[ -x /usr/local/bin/bash ]]; then
        macos_path="/usr/local/bin:$macos_path"
    fi

    echo "Running $test_script (HOME=$tmp_home)..."
    local rc=0
    HOME="$tmp_home" N2_DIR="$N2_ROOT" PATH="$macos_path" bash "$test_script" 2>&1 || rc=$?
    rm -rf "$tmp_home"
    if [[ $rc -eq 0 ]]; then
        echo "✅ $label passed"
        RESULTS+=("PASS $label")
        PASS_TOTAL=$((PASS_TOTAL + 1))
    else
        echo "❌ $label failed"
        RESULTS+=("FAIL $label")
        FAIL_TOTAL=$((FAIL_TOTAL + 1))
    fi
}

run_test_docker() {
    local platform=$1
    local test_name=$2
    local dockerfile="$SCRIPT_DIR/platforms/${platform}.Dockerfile"
    local test_script="tests/e2e/tests/${test_name}.sh"
    local image_tag="n2-e2e-${platform}"
    local label="${platform}/${test_name}"

    if [[ ! -f "$dockerfile" ]]; then
        echo "⚠️  Dockerfile not found: $dockerfile — skipping $label"
        RESULTS+=("SKIP $label (no Dockerfile)")
        return
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🐳 $label"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Build the image
    echo "Building image $image_tag..."
    if ! docker build -t "$image_tag" -f "$dockerfile" "$N2_ROOT" 2>&1; then
        echo "❌ Build failed for $label"
        RESULTS+=("FAIL $label (build failed)")
        FAIL_TOTAL=$((FAIL_TOTAL + 1))
        return
    fi

    # Run the test inside the container
    echo "Running $test_script..."
    if docker run --rm "$image_tag" bash "$test_script" 2>&1; then
        echo "✅ $label passed"
        RESULTS+=("PASS $label")
        PASS_TOTAL=$((PASS_TOTAL + 1))
    else
        echo "❌ $label failed"
        RESULTS+=("FAIL $label")
        FAIL_TOTAL=$((FAIL_TOTAL + 1))
    fi
}

run_test() {
    local platform=$1
    local test_name=$2
    if [[ "$platform" == "macos" ]]; then
        run_test_macos "$platform" "$test_name"
    else
        run_test_docker "$platform" "$test_name"
    fi
}

echo "🧪 n2 E2E Test Runner"
echo "Platforms: ${SELECTED_PLATFORMS[*]}"
echo "Tests:     ${SELECTED_TESTS[*]}"

for platform in "${SELECTED_PLATFORMS[@]}"; do
    for test in "${SELECTED_TESTS[@]}"; do
        run_test "$platform" "$test"
    done
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for result in "${RESULTS[@]}"; do
    echo "  $result"
done
echo ""
echo "Total: $PASS_TOTAL passed, $FAIL_TOTAL failed"

[[ $FAIL_TOTAL -eq 0 ]] || exit 1
echo "🎉 All tests passed!"
