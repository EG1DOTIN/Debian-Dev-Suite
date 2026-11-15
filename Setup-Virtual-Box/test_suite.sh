#!/usr/bin/env bash
# ==============================================================================
# Script: test_suite.sh
# Description: Automated test suite for setup_virtualbox_secure.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/setup_virtualbox_secure.sh"
PASS=0
FAIL=0

log_test() {
    echo -e "\n\033[1;34m[TEST]\033[0m $1"
}

assert_success() {
    if "$@"; then
        echo -e "\033[0;32m[PASS]\033[0m Command succeeded as expected."
        PASS=$((PASS + 1))
    else
        echo -e "\033[0;31m[FAIL]\033[0m Command failed unexpectedly: $*"
        FAIL=$((FAIL + 1))
    fi
}

assert_failure() {
    if "$@"; then
        echo -e "\033[0;31m[FAIL]\033[0m Command succeeded but was expected to fail: $*"
        FAIL=$((FAIL + 1))
    else
        echo -e "\033[0;32m[PASS]\033[0m Command failed as expected."
        PASS=$((PASS + 1))
    fi
}

echo "=========================================================="
echo " Starting Automated Test Suite for VirtualBox Setup Script"
echo "=========================================================="

# Test 1: Help message
log_test "Verify --help flag displays usage and security details"
assert_success $SCRIPT --help > /dev/null

# Test 2: Dry-run mode
log_test "Verify --dry-run completes without error"
assert_success $SCRIPT --dry-run --user "$(id -un)" > /dev/null

# Test 3: Harden-only dry run
log_test "Verify --harden-only with --dry-run"
assert_success $SCRIPT --harden-only --dry-run --user "$(id -un)" > /dev/null

# Test 4: Checksum verification with matching SHA256
log_test "Verify SHA256 verification PASS with valid checksum"
TMP_DIR="$(mktemp -d)"
echo "sample-installer-binary-data" > "${TMP_DIR}/VirtualBox-test.run"
sha256sum "${TMP_DIR}/VirtualBox-test.run" > "${TMP_DIR}/SHA256SUMS"
assert_success $SCRIPT --dry-run --user "$(id -un)" --package-file "${TMP_DIR}/VirtualBox-test.run" --checksum-file "${TMP_DIR}/SHA256SUMS" > /dev/null

# Test 5: Checksum verification with tampered file
log_test "Verify SHA256 verification FAIL on tampered package"
echo "tampered-content-malicious-bytes" > "${TMP_DIR}/VirtualBox-test.run"
assert_failure $SCRIPT --dry-run --user "$(id -un)" --package-file "${TMP_DIR}/VirtualBox-test.run" --checksum-file "${TMP_DIR}/SHA256SUMS" > /dev/null
rm -rf "${TMP_DIR}"

# Test 6: Invalid user validation
log_test "Verify failure when non-existent user is passed"
assert_failure $SCRIPT --dry-run --user non_existent_user_998877 > /dev/null

# Test 7: Uninstall dry run
log_test "Verify --uninstall with --dry-run executes successfully"
assert_success $SCRIPT --uninstall --dry-run --user "$(id -un)" > /dev/null

# Test 8: Uninstall with purge dry run
log_test "Verify --uninstall --purge with --dry-run executes successfully"
assert_success $SCRIPT --uninstall --purge --dry-run --user "$(id -un)" > /dev/null

echo "=========================================================="
echo " Test Results: ${PASS} Passed, ${FAIL} Failed"
echo "=========================================================="

if [[ "${FAIL}" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
