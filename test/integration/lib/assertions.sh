#!/usr/bin/env bash
#
# Assertion Library for sops_rails Integration Tests
#
# This file provides reusable assertion functions that can be sourced
# by test scripts. It's designed to be standalone and framework-agnostic.
#
# Usage:
#   source "$(dirname "$0")/lib/assertions.sh"
#
# All assertions return 0 on success, 1 on failure, and update global counters:
#   TESTS_RUN, TESTS_PASSED, TESTS_FAILED
#
# ------------------------------------------------------------------------------

# Initialize counters if not already set
: "${TESTS_RUN:=0}"
: "${TESTS_PASSED:=0}"
: "${TESTS_FAILED:=0}"
: "${VERBOSE:=false}"

# Colors (can be overridden)
: "${RED:=\033[0;31m}"
: "${GREEN:=\033[0;32m}"
: "${YELLOW:=\033[0;33m}"
: "${NC:=\033[0m}"

# ==============================================================================
# Logging Helpers
# ==============================================================================

_assert_log_success() {
  echo -e "${GREEN}[PASS]${NC} $1"
}

_assert_log_fail() {
  echo -e "${RED}[FAIL]${NC} $1"
}

_assert_log_output() {
  local label="$1"
  local content="$2"
  echo -e "${YELLOW}[$label]${NC}"
  echo "$content" | sed 's/^/  │ /'
}

_assert_log_debug() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo -e "${YELLOW}[DEBUG]${NC} $1"
  fi
}

# ==============================================================================
# Basic Assertions
# ==============================================================================

# Assert that a condition is true
# Usage: assert_true "description" <condition>
# Example: assert_true "X equals 5" [[ $X -eq 5 ]]
assert_true() {
  local description="$1"
  shift
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if eval "$@"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "CONDITION" "$*"
    return 1
  fi
}

# Assert that a condition is false
# Usage: assert_false "description" <condition>
assert_false() {
  local description="$1"
  shift
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if ! eval "$@"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "CONDITION (expected false)" "$*"
    return 1
  fi
}

# ==============================================================================
# Command Assertions
# ==============================================================================

# Assert that a command succeeds (exit code 0)
# Usage: assert_success "description" command [args...]
assert_success() {
  local description="$1"
  shift
  
  TESTS_RUN=$((TESTS_RUN + 1))
  _assert_log_debug "Running: $*"
  
  local output
  local exit_code=0
  output=$("$@" 2>&1) || exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    if [[ "$VERBOSE" == "true" && -n "$output" ]]; then
      _assert_log_output "OUTPUT" "$output"
    fi
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "COMMAND" "$*"
    _assert_log_output "EXIT CODE" "$exit_code"
    [[ -n "$output" ]] && _assert_log_output "OUTPUT" "$output"
    return 1
  fi
}

# Assert that a command fails (non-zero exit code)
# Usage: assert_failure "description" command [args...]
assert_failure() {
  local description="$1"
  shift
  
  TESTS_RUN=$((TESTS_RUN + 1))
  _assert_log_debug "Running (expecting failure): $*"
  
  local output
  local exit_code=0
  output=$("$@" 2>&1) || exit_code=$?
  
  if [[ $exit_code -ne 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description (expected failure, got exit code $exit_code)"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description (expected failure but command succeeded)"
    _assert_log_output "COMMAND" "$*"
    [[ -n "$output" ]] && _assert_log_output "OUTPUT" "$output"
    return 1
  fi
}

# Assert command exits with specific code
# Usage: assert_exit_code "description" expected_code command [args...]
assert_exit_code() {
  local description="$1"
  local expected_code="$2"
  shift 2
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  local output
  local exit_code=0
  output=$("$@" 2>&1) || exit_code=$?
  
  if [[ $exit_code -eq $expected_code ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "EXPECTED EXIT CODE" "$expected_code"
    _assert_log_output "ACTUAL EXIT CODE" "$exit_code"
    [[ -n "$output" ]] && _assert_log_output "OUTPUT" "$output"
    return 1
  fi
}

# ==============================================================================
# String Assertions
# ==============================================================================

# Assert two strings are equal
# Usage: assert_equals "description" "expected" "actual"
assert_equals() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "EXPECTED" "$expected"
    _assert_log_output "ACTUAL" "$actual"
    return 1
  fi
}

# Assert two strings are not equal
# Usage: assert_not_equals "description" "unexpected" "actual"
assert_not_equals() {
  local description="$1"
  local unexpected="$2"
  local actual="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ "$unexpected" != "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "SHOULD NOT EQUAL" "$unexpected"
    _assert_log_output "BUT WAS" "$actual"
    return 1
  fi
}

# Assert string is not empty
# Usage: assert_not_empty "description" "$variable"
assert_not_empty() {
  local description="$1"
  local value="$2"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ -n "$value" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description (value is empty)"
    return 1
  fi
}

# Assert string is empty
# Usage: assert_empty "description" "$variable"
assert_empty() {
  local description="$1"
  local value="$2"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ -z "$value" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description (expected empty, got: '$value')"
    return 1
  fi
}

# Assert string contains substring
# Usage: assert_contains "description" "haystack" "needle"
assert_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ "$haystack" == *"$needle"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "EXPECTED TO CONTAIN" "$needle"
    _assert_log_output "ACTUAL STRING" "$haystack"
    return 1
  fi
}

# Assert string does not contain substring
# Usage: assert_not_contains "description" "haystack" "needle"
assert_not_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ "$haystack" != *"$needle"* ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "SHOULD NOT CONTAIN" "$needle"
    _assert_log_output "ACTUAL STRING" "$haystack"
    return 1
  fi
}

# Assert string matches regex
# Usage: assert_matches "description" "string" "pattern"
assert_matches() {
  local description="$1"
  local string="$2"
  local pattern="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ "$string" =~ $pattern ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "EXPECTED TO MATCH" "$pattern"
    _assert_log_output "ACTUAL STRING" "$string"
    return 1
  fi
}

# ==============================================================================
# Output Assertions
# ==============================================================================

# Assert that command output contains a specific string
# Usage: assert_output_contains "description" "expected" command [args...]
assert_output_contains() {
  local description="$1"
  local expected="$2"
  shift 2
  
  TESTS_RUN=$((TESTS_RUN + 1))
  _assert_log_debug "Running: $*"
  
  local output
  local exit_code=0
  output=$("$@" 2>&1) || exit_code=$?
  
  if echo "$output" | grep -q "$expected"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    [[ "$VERBOSE" == "true" ]] && _assert_log_output "OUTPUT" "$output"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "COMMAND" "$*"
    _assert_log_output "EXPECTED TO CONTAIN" "$expected"
    _assert_log_output "ACTUAL OUTPUT" "$output"
    return 1
  fi
}

# Assert that command output does NOT contain a specific string
# Usage: assert_output_not_contains "description" "unexpected" command [args...]
assert_output_not_contains() {
  local description="$1"
  local unexpected="$2"
  shift 2
  
  TESTS_RUN=$((TESTS_RUN + 1))
  _assert_log_debug "Running: $*"
  
  local output
  local exit_code=0
  output=$("$@" 2>&1) || exit_code=$?
  
  if ! echo "$output" | grep -q "$unexpected"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "COMMAND" "$*"
    _assert_log_output "SHOULD NOT CONTAIN" "$unexpected"
    _assert_log_output "ACTUAL OUTPUT" "$output"
    return 1
  fi
}

# Assert that command output matches a regex
# Usage: assert_output_matches "description" "pattern" command [args...]
assert_output_matches() {
  local description="$1"
  local pattern="$2"
  shift 2
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  local output
  local exit_code=0
  output=$("$@" 2>&1) || exit_code=$?
  
  if echo "$output" | grep -qE "$pattern"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "EXPECTED TO MATCH" "$pattern"
    _assert_log_output "ACTUAL OUTPUT" "$output"
    return 1
  fi
}

# ==============================================================================
# File Assertions
# ==============================================================================

# Assert that a file exists
# Usage: assert_file_exists "description" /path/to/file
assert_file_exists() {
  local description="$1"
  local file_path="$2"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ -f "$file_path" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "EXPECTED FILE" "$file_path"
    return 1
  fi
}

# Assert that a file does not exist
# Usage: assert_file_not_exists "description" /path/to/file
assert_file_not_exists() {
  local description="$1"
  local file_path="$2"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ ! -f "$file_path" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "UNEXPECTED FILE EXISTS" "$file_path"
    return 1
  fi
}

# Assert that a directory exists
# Usage: assert_dir_exists "description" /path/to/dir
assert_dir_exists() {
  local description="$1"
  local dir_path="$2"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ -d "$dir_path" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "EXPECTED DIRECTORY" "$dir_path"
    return 1
  fi
}

# Assert that a file contains a specific string
# Usage: assert_file_contains "description" /path/to/file "expected"
assert_file_contains() {
  local description="$1"
  local file_path="$2"
  local expected="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ ! -f "$file_path" ]]; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description (file does not exist: $file_path)"
    return 1
  fi
  
  if grep -q "$expected" "$file_path" 2>/dev/null; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "FILE" "$file_path"
    _assert_log_output "EXPECTED TO CONTAIN" "$expected"
    _assert_log_output "ACTUAL CONTENT" "$(cat "$file_path" 2>/dev/null || echo '<unable to read>')"
    return 1
  fi
}

# Assert that a file does not contain a specific string
# Usage: assert_file_not_contains "description" /path/to/file "unexpected"
assert_file_not_contains() {
  local description="$1"
  local file_path="$2"
  local unexpected="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ ! -f "$file_path" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description (file does not exist)"
    return 0
  fi
  
  if ! grep -q "$unexpected" "$file_path" 2>/dev/null; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "FILE" "$file_path"
    _assert_log_output "SHOULD NOT CONTAIN" "$unexpected"
    return 1
  fi
}

# Assert file is not empty
# Usage: assert_file_not_empty "description" /path/to/file
assert_file_not_empty() {
  local description="$1"
  local file_path="$2"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ -s "$file_path" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description (file is empty or does not exist)"
    _assert_log_output "FILE" "$file_path"
    return 1
  fi
}

# ==============================================================================
# Numeric Assertions
# ==============================================================================

# Assert number is greater than
# Usage: assert_greater_than "description" actual minimum
assert_greater_than() {
  local description="$1"
  local actual="$2"
  local minimum="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ $actual -gt $minimum ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "EXPECTED" "> $minimum"
    _assert_log_output "ACTUAL" "$actual"
    return 1
  fi
}

# Assert number is less than
# Usage: assert_less_than "description" actual maximum
assert_less_than() {
  local description="$1"
  local actual="$2"
  local maximum="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ $actual -lt $maximum ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    _assert_log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    _assert_log_fail "$description"
    _assert_log_output "EXPECTED" "< $maximum"
    _assert_log_output "ACTUAL" "$actual"
    return 1
  fi
}

# ==============================================================================
# Test Summary
# ==============================================================================

# Print test summary
# Usage: print_test_summary
print_test_summary() {
  echo ""
  echo -e "${NC}════════════════════════════════════════════════════════════════════════${NC}"
  echo "  TEST SUMMARY"
  echo -e "════════════════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  Tests Run:    ${TESTS_RUN}"
  echo -e "  ${GREEN}Passed:${NC}       ${TESTS_PASSED}"
  echo -e "  ${RED}Failed:${NC}       ${TESTS_FAILED}"
  echo ""
  
  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    return 0
  else
    echo -e "${RED}✗ ${TESTS_FAILED} test(s) failed${NC}"
    return 1
  fi
}

# Reset test counters
# Usage: reset_test_counters
reset_test_counters() {
  TESTS_RUN=0
  TESTS_PASSED=0
  TESTS_FAILED=0
}
