#!/bin/bash
# Test script: Verify that chmod is blocked in Docker workspace for agent
# This ensures agents running in the docker container cannot execute chmod

set -euo pipefail

echo "Testing chmod blocking in Docker workspace..."
echo "=============================================="
echo

# Helper function to test a chmod pattern
test_chmod_blocked() {
    local pattern="$1"
    local result
    result=$(PROJECT_ROOT=$PWD/claude-plugin ./run-docker-workspace.sh "bash -c 'chmod $pattern /workspace/test.sh 2>&1; echo EXIT_CODE=\$?'" 2>&1)

    if echo "$result" | grep -q "proxy_wrapper.*blocked"; then
        echo "✓ PASS: chmod $pattern correctly blocked"
        return 0
    else
        echo "✗ FAIL: chmod $pattern was not blocked!"
        echo "  Output: $result"
        return 1
    fi
}

# Test various chmod patterns
test_chmod_blocked "+x" || exit 1
test_chmod_blocked "755" || exit 1
test_chmod_blocked "u+x" || exit 1
test_chmod_blocked "a+x" || exit 1
test_chmod_blocked "-R +x" || exit 1
test_chmod_blocked "--reference=file" || exit 1
echo

# Verify config is properly structured
echo "Verifying cli_wrapper config..."
if grep -q '"chmod"' ./docker-scripts/cli_wrapper_rules.json; then
    echo "✓ PASS: chmod rule found in config"
else
    echo "✗ FAIL: chmod rule not in config"
    exit 1
fi

if grep -q '"denied_patterns".*"\.\*"' ./docker-scripts/cli_wrapper_rules.json; then
    echo "✓ PASS: chmod has catch-all deny pattern"
else
    echo "✗ FAIL: chmod does not have catch-all deny pattern"
    exit 1
fi
echo

echo "=============================================="
echo "All chmod blocking tests PASSED ✓"
echo
echo "Summary:"
echo "  • chmod is configured to be completely blocked in /workspace"
echo "  • cli_wrapper (installed in the claude-plugin venv) uses a catch-all deny pattern for chmod"
echo "  • Agents running in Docker CANNOT modify file permissions"
