#!/usr/bin/env bash
# ==============================================================================
# Setup-Hinglish & Easy Hindi Typing Test Suite
# Validates offline engine, dictionaries, scripts, security & privacy integrity
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${SCRIPT_DIR}/easy-hindi-typing"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local name="$1"
    local cmd="$2"
    echo -n "Testing ${name}... "
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

echo "=================================================================="
echo "  Setup-Hinglish & Easy Hindi Typing Test Suite"
echo "=================================================================="

# 1. Shell Script Syntax & Flag Checks
run_test "hinglish-to-hindi-typing.sh syntax (bash -n)" "bash -n ${SCRIPT_DIR}/hinglish-to-hindi-typing.sh"
run_test "easy-hindi-typing.sh syntax (bash -n)" "bash -n ${SCRIPT_DIR}/easy-hindi-typing.sh"
run_test "hinglish-to-hindi-typing.sh --help (no unbound vars)" "${SCRIPT_DIR}/hinglish-to-hindi-typing.sh --help"
run_test "hinglish-to-hindi-typing.sh --test (no unbound vars)" "${SCRIPT_DIR}/hinglish-to-hindi-typing.sh --test"
run_test "easy-hindi-typing.sh --help execution" "${SCRIPT_DIR}/easy-hindi-typing.sh --help"


# 2. Python Server Syntax Check
run_test "server.py syntax (python3 -m py_compile)" "python3 -m py_compile ${APP_DIR}/server.py"

# 3. Privacy & Offline Integrity (No external CDN scripts or stylesheet links)
run_test "Zero external CDN references in index.html" "! grep -E 'https?://' ${APP_DIR}/index.html"
run_test "Zero external CDN references in style.css" "! grep -E 'https?://' ${APP_DIR}/style.css"
run_test "Zero external CDN references in app.js" "! grep -E 'https?://' ${APP_DIR}/app.js"
run_test "Zero external CDN references in words.js" "! grep -E 'https?://' ${APP_DIR}/words.js"
run_test "Zero external CDN references in transliterate.js" "! grep -E 'https?://' ${APP_DIR}/transliterate.js"

# 4. Transliteration & Word Engine Node.js Unit Tests
run_test "Node.js phonetic engine loads words & transliterate" "node -e '
  require(\"${APP_DIR}/words.js\");
  const engine = require(\"${APP_DIR}/transliterate.js\");
  if (!engine.getSuggestions) process.exit(1);
'"

run_test "Hinglish suggestion: 'namaste' -> 'नमस्ते'" "node -e '
  require(\"${APP_DIR}/words.js\");
  const engine = require(\"${APP_DIR}/transliterate.js\");
  const cands = engine.getSuggestions(\"namaste\");
  if (!cands.includes(\"नमस्ते\")) process.exit(1);
'"

run_test "Hinglish suggestion: 'kya' -> 'क्या'" "node -e '
  require(\"${APP_DIR}/words.js\");
  const engine = require(\"${APP_DIR}/transliterate.js\");
  const cands = engine.getSuggestions(\"kya\");
  if (!cands.includes(\"क्या\")) process.exit(1);
'"

run_test "Hinglish suggestion: 'bharat' -> 'भारत'" "node -e '
  require(\"${APP_DIR}/words.js\");
  const engine = require(\"${APP_DIR}/transliterate.js\");
  const cands = engine.getSuggestions(\"bharat\");
  if (!cands.includes(\"भारत\")) process.exit(1);
'"

run_test "Hinglish suggestion: 'dhanyavaad' -> 'धन्यवाद'" "node -e '
  require(\"${APP_DIR}/words.js\");
  const engine = require(\"${APP_DIR}/transliterate.js\");
  const cands = engine.getSuggestions(\"dhanyavaad\");
  if (!cands.includes(\"धन्यवाद\")) process.exit(1);
'"

run_test "Hinglish suggestion: 'pratham' -> 'प्रथम'" "node -e '
  require(\"${APP_DIR}/words.js\");
  const engine = require(\"${APP_DIR}/transliterate.js\");
  const cands = engine.getSuggestions(\"pratham\");
  if (!cands.includes(\"प्रथम\")) process.exit(1);
'"

# 5. DOM & File Integrity
run_test "index.html has editorArea textarea" "grep -q 'id=\"editorArea\"' ${APP_DIR}/index.html"
run_test "index.html has suggestionsBox" "grep -q 'id=\"suggestionsBox\"' ${APP_DIR}/index.html"
run_test "index.html has caretMirror" "grep -q 'id=\"caretMirror\"' ${APP_DIR}/index.html"
run_test "index.html has symbolsBar" "grep -q 'id=\"symbolsBar\"' ${APP_DIR}/index.html"
run_test "index.html has copyBtn" "grep -q 'id=\"copyBtn\"' ${APP_DIR}/index.html"
run_test "index.html has downloadBtn" "grep -q 'id=\"downloadBtn\"' ${APP_DIR}/index.html"

# 6. Desktop File Integrity
run_test "Desktop launcher syntax & icon existence" "[ -f ${APP_DIR}/easy-hindi-typing.desktop ] && [ -f ${APP_DIR}/icon.svg ]"

echo "=================================================================="
echo -e "Tests Completed: ${GREEN}${PASSED_TESTS} Passed${NC}, ${RED}${FAILED_TESTS} Failed${NC}"
echo "=================================================================="

if [ "${FAILED_TESTS}" -gt 0 ]; then
    exit 1
fi
exit 0
