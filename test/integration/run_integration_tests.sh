#!/usr/bin/env bash
#
# sops_rails Integration Test Suite
#
# This script performs end-to-end integration tests for the sops_rails gem
# using actual SOPS/age encryption. It tests the full cycle:
#   - sops:init (initialize project)
#   - sops:edit (create/edit encrypted credentials)
#   - sops:show (view decrypted credentials)
#
# Usage:
#   ./test/integration/run_integration_tests.sh
#   ./test/integration/run_integration_tests.sh --verbose
#   ./test/integration/run_integration_tests.sh --keep-sandbox
#
# Requirements:
#   - SOPS binary installed (brew install sops / apt install sops)
#   - age binary installed (brew install age / apt install age)
#   - Ruby with bundler
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Prerequisites not met
#
# Author: sops_rails team
# ------------------------------------------------------------------------------

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SANDBOX_DIR="${SCRIPT_DIR}/sandbox"
SANDBOX_KEYS_DIR="${SANDBOX_DIR}/.config/sops/age"
VERBOSE="${VERBOSE:-false}"
KEEP_SANDBOX="${KEEP_SANDBOX:-false}"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output (disabled if not a terminal)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  BOLD=''
  NC=''
fi

# ==============================================================================
# Logging Functions
# ==============================================================================

log_header() {
  echo ""
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  $1${NC}"
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
}

log_section() {
  echo ""
  echo -e "${CYAN}──────────────────────────────────────────────────────────────${NC}"
  echo -e "${CYAN}  $1${NC}"
  echo -e "${CYAN}──────────────────────────────────────────────────────────────${NC}"
}

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_debug() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo -e "${YELLOW}[DEBUG]${NC} $1"
  fi
}

log_output() {
  local label="$1"
  local content="$2"
  echo -e "${YELLOW}[$label]${NC}"
  echo "$content" | sed 's/^/  │ /'
}

# ==============================================================================
# Assertion Functions
# ==============================================================================

# Assert that a command succeeds (exit code 0)
# Usage: assert_success "description" command [args...]
assert_success() {
  local description="$1"
  shift
  local cmd="$*"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  log_debug "Running: $cmd"
  
  local output
  local exit_code=0
  output=$("$@" 2>&1) || exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "$description"
    if [[ "$VERBOSE" == "true" && -n "$output" ]]; then
      log_output "OUTPUT" "$output"
    fi
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_fail "$description"
    log_output "COMMAND" "$cmd"
    log_output "EXIT CODE" "$exit_code"
    if [[ -n "$output" ]]; then
      log_output "OUTPUT" "$output"
    fi
    return 1
  fi
}

# Assert that a command fails (non-zero exit code)
# Usage: assert_failure "description" command [args...]
assert_failure() {
  local description="$1"
  shift
  local cmd="$*"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  log_debug "Running (expecting failure): $cmd"
  
  local output
  local exit_code=0
  output=$("$@" 2>&1) || exit_code=$?
  
  if [[ $exit_code -ne 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "$description (expected failure, got exit code $exit_code)"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_fail "$description (expected failure but command succeeded)"
    log_output "COMMAND" "$cmd"
    if [[ -n "$output" ]]; then
      log_output "OUTPUT" "$output"
    fi
    return 1
  fi
}

# Assert that a file exists
# Usage: assert_file_exists "description" /path/to/file
assert_file_exists() {
  local description="$1"
  local file_path="$2"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ -f "$file_path" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_fail "$description"
    log_output "EXPECTED FILE" "$file_path"
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
    log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_fail "$description"
    log_output "UNEXPECTED FILE EXISTS" "$file_path"
    return 1
  fi
}

# Assert that a file contains a specific string
# Usage: assert_file_contains "description" /path/to/file "expected string"
assert_file_contains() {
  local description="$1"
  local file_path="$2"
  local expected="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ ! -f "$file_path" ]]; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_fail "$description (file does not exist: $file_path)"
    return 1
  fi
  
  if grep -q "$expected" "$file_path" 2>/dev/null; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_fail "$description"
    log_output "FILE" "$file_path"
    log_output "EXPECTED TO CONTAIN" "$expected"
    log_output "ACTUAL CONTENT" "$(cat "$file_path" 2>/dev/null || echo '<unable to read>')"
    return 1
  fi
}

# Assert that command output contains a specific string
# Usage: assert_output_contains "description" "expected string" command [args...]
assert_output_contains() {
  local description="$1"
  local expected="$2"
  shift 2
  local cmd="$*"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  log_debug "Running: $cmd"
  
  local output
  local exit_code=0
  output=$("$@" 2>&1) || exit_code=$?
  
  if echo "$output" | grep -q "$expected"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "$description"
    if [[ "$VERBOSE" == "true" ]]; then
      log_output "OUTPUT" "$output"
    fi
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_fail "$description"
    log_output "COMMAND" "$cmd"
    log_output "EXPECTED TO CONTAIN" "$expected"
    log_output "ACTUAL OUTPUT" "$output"
    return 1
  fi
}

# Assert that command output does NOT contain a specific string
# Usage: assert_output_not_contains "description" "unexpected string" command [args...]
assert_output_not_contains() {
  local description="$1"
  local unexpected="$2"
  shift 2
  local cmd="$*"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  log_debug "Running: $cmd"
  
  local output
  local exit_code=0
  output=$("$@" 2>&1) || exit_code=$?
  
  if ! echo "$output" | grep -q "$unexpected"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_fail "$description"
    log_output "COMMAND" "$cmd"
    log_output "SHOULD NOT CONTAIN" "$unexpected"
    log_output "ACTUAL OUTPUT" "$output"
    return 1
  fi
}

# Assert two strings are equal
# Usage: assert_equals "description" "expected" "actual"
assert_equals() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_fail "$description"
    log_output "EXPECTED" "$expected"
    log_output "ACTUAL" "$actual"
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
    log_success "$description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    log_fail "$description (value is empty)"
    return 1
  fi
}

# ==============================================================================
# Environment & Sandbox Management
# ==============================================================================

# Create isolated test sandbox with its own age keys
setup_sandbox() {
  local sandbox_name="${1:-default}"
  local sandbox_path="${SANDBOX_DIR}/${sandbox_name}"
  
  # Log to stderr so it doesn't pollute the returned path
  log_info "Setting up sandbox: $sandbox_name" >&2
  
  # Clean up existing sandbox
  rm -rf "$sandbox_path"
  mkdir -p "$sandbox_path"
  mkdir -p "${sandbox_path}/.config/sops/age"
  mkdir -p "${sandbox_path}/config"
  
  # Create minimal Gemfile that references local gem (minimal deps)
  cat > "${sandbox_path}/Gemfile" << EOF
source "https://rubygems.org"

gem "sops_rails", path: "${GEM_ROOT}"
gem "rake"
EOF

  # Create Rakefile that loads sops tasks
  cat > "${sandbox_path}/Rakefile" << 'EOF'
require "bundler/setup"
require "sops_rails"
load "sops_rails/tasks/sops.rake"
EOF

  # Return only the path
  echo "$sandbox_path"
}

# Clean up sandbox
cleanup_sandbox() {
  local sandbox_name="${1:-default}"
  local sandbox_path="${SANDBOX_DIR}/${sandbox_name}"
  
  if [[ "$KEEP_SANDBOX" != "true" ]]; then
    log_debug "Cleaning up sandbox: $sandbox_name"
    rm -rf "$sandbox_path"
  else
    log_info "Keeping sandbox at: $sandbox_path"
  fi
}

# Clean up all sandboxes
cleanup_all_sandboxes() {
  if [[ "$KEEP_SANDBOX" != "true" ]]; then
    log_debug "Cleaning up all sandboxes"
    rm -rf "$SANDBOX_DIR"
  fi
}

# Generate age key for sandbox
generate_sandbox_age_key() {
  local sandbox_path="$1"
  local keys_file="${sandbox_path}/.config/sops/age/keys.txt"
  
  mkdir -p "$(dirname "$keys_file")"
  age-keygen -o "$keys_file" 2>/dev/null
  
  # Extract public key
  grep "public key:" "$keys_file" | cut -d: -f2 | tr -d ' '
}

# Get public key from sandbox
get_sandbox_public_key() {
  local sandbox_path="$1"
  local keys_file="${sandbox_path}/.config/sops/age/keys.txt"
  
  if [[ -f "$keys_file" ]]; then
    grep "public key:" "$keys_file" | cut -d: -f2 | tr -d ' '
  else
    echo ""
  fi
}

# Run rake task in sandbox with isolated age key
run_in_sandbox() {
  local sandbox_path="$1"
  shift
  local cmd="$*"
  
  # Set up isolated environment
  export SOPS_AGE_KEY_FILE="${sandbox_path}/.config/sops/age/keys.txt"
  export HOME="${sandbox_path}"
  
  cd "$sandbox_path"
  bundle install --quiet 2>/dev/null || bundle install
  
  # Run command
  eval "$cmd"
}

# Run rake task in sandbox (simplified)
run_rake_in_sandbox() {
  local sandbox_path="$1"
  local task="$2"
  shift 2
  local extra_args="$*"
  
  export SOPS_AGE_KEY_FILE="${sandbox_path}/.config/sops/age/keys.txt"
  export HOME="${sandbox_path}"
  
  cd "$sandbox_path"
  bundle exec rake "$task" $extra_args
}

# ==============================================================================
# Prerequisite Checks
# ==============================================================================

check_prerequisites() {
  log_header "Checking Prerequisites"
  
  local prereq_failed=false
  
  # Check SOPS
  if command -v sops &>/dev/null; then
    local sops_version
    sops_version=$(sops --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    log_success "SOPS binary found (v${sops_version})"
  else
    log_fail "SOPS binary not found"
    log_info "Install with: brew install sops (macOS) or apt install sops (Debian/Ubuntu)"
    prereq_failed=true
  fi
  
  # Check age
  if command -v age &>/dev/null; then
    log_success "age binary found"
  else
    log_fail "age binary not found"
    log_info "Install with: brew install age (macOS) or apt install age (Debian/Ubuntu)"
    prereq_failed=true
  fi
  
  # Check age-keygen
  if command -v age-keygen &>/dev/null; then
    log_success "age-keygen binary found"
  else
    log_fail "age-keygen binary not found"
    prereq_failed=true
  fi
  
  # Check Ruby
  if command -v ruby &>/dev/null; then
    local ruby_version
    ruby_version=$(ruby --version | cut -d' ' -f2)
    log_success "Ruby found (v${ruby_version})"
  else
    log_fail "Ruby not found"
    prereq_failed=true
  fi
  
  # Check Bundler
  if command -v bundle &>/dev/null; then
    log_success "Bundler found"
  else
    log_fail "Bundler not found"
    log_info "Install with: gem install bundler"
    prereq_failed=true
  fi
  
  # Check gem root exists
  if [[ -f "${GEM_ROOT}/sops_rails.gemspec" ]]; then
    log_success "sops_rails gem found at ${GEM_ROOT}"
  else
    log_fail "sops_rails gem not found at ${GEM_ROOT}"
    prereq_failed=true
  fi
  
  if [[ "$prereq_failed" == "true" ]]; then
    echo ""
    log_fail "Prerequisites check failed. Please install missing dependencies."
    return 2
  fi
  
  log_info "All prerequisites satisfied"
  return 0
}

# ==============================================================================
# Test Scenarios
# ==============================================================================

# Test: Basic initialization without existing configuration
test_basic_init() {
  log_section "Test: Basic sops:init (fresh project)"
  
  local sandbox
  sandbox=$(setup_sandbox "basic_init")
  
  # Run init in non-interactive mode
  assert_success "sops:init completes successfully" \
    run_rake_in_sandbox "$sandbox" "sops:init" "NON_INTERACTIVE=1"
  
  # Verify created files
  assert_file_exists ".sops.yaml was created" "${sandbox}/.sops.yaml"
  assert_file_exists "credentials.yaml.enc was created" "${sandbox}/config/credentials.yaml.enc"
  
  # Verify .sops.yaml contains age key
  local public_key
  public_key=$(get_sandbox_public_key "$sandbox")
  assert_file_contains ".sops.yaml contains public key" "${sandbox}/.sops.yaml" "$public_key"
  
  # Verify credentials file is encrypted (contains SOPS metadata)
  assert_file_contains "credentials.yaml.enc is SOPS-encrypted" \
    "${sandbox}/config/credentials.yaml.enc" "sops"
  
  cleanup_sandbox "basic_init"
}

# Test: sops:show displays decrypted content
test_sops_show() {
  log_section "Test: sops:show (view decrypted credentials)"
  
  local sandbox
  sandbox=$(setup_sandbox "sops_show")
  
  # Initialize first
  run_rake_in_sandbox "$sandbox" "sops:init" "NON_INTERACTIVE=1" >/dev/null 2>&1
  
  # Run sops:show and capture output
  local show_output
  show_output=$(run_rake_in_sandbox "$sandbox" "sops:show" 2>&1)
  
  # Verify it shows decrypted content (template has these)
  assert_output_contains "sops:show displays aws section" "aws:" echo "$show_output"
  assert_output_contains "sops:show displays database section" "database:" echo "$show_output"
  
  # Verify it does NOT contain SOPS metadata (it's decrypted)
  assert_output_not_contains "sops:show output is decrypted (no sops metadata)" \
    "ENC\[AES" echo "$show_output"
  
  cleanup_sandbox "sops_show"
}

# Test: sops:show with specific file path
test_sops_show_with_file_path() {
  log_section "Test: sops:show with explicit file path"
  
  local sandbox
  sandbox=$(setup_sandbox "sops_show_path")
  
  # Initialize
  run_rake_in_sandbox "$sandbox" "sops:init" "NON_INTERACTIVE=1" >/dev/null 2>&1
  
  # Run sops:show with explicit path
  local show_output
  show_output=$(run_rake_in_sandbox "$sandbox" "sops:show[config/credentials.yaml.enc]" 2>&1)
  
  assert_output_contains "sops:show[path] displays content" "aws:" echo "$show_output"
  
  cleanup_sandbox "sops_show_path"
}

# Test: sops:show fails for non-existent file
test_sops_show_nonexistent_file() {
  log_section "Test: sops:show with non-existent file"
  
  local sandbox
  sandbox=$(setup_sandbox "sops_show_fail")
  
  # Initialize
  run_rake_in_sandbox "$sandbox" "sops:init" "NON_INTERACTIVE=1" >/dev/null 2>&1
  
  # Run sops:show with non-existent file (should fail)
  assert_failure "sops:show fails for non-existent file" \
    run_rake_in_sandbox "$sandbox" "sops:show[nonexistent.yaml.enc]"
  
  cleanup_sandbox "sops_show_fail"
}

# Test: sops:edit task exists and accepts file argument
# Note: Testing the actual edit is tricky as it requires interactive editor
test_sops_edit_task() {
  log_section "Test: sops:edit task availability"
  
  local sandbox
  sandbox=$(setup_sandbox "sops_edit_task")
  
  # Initialize
  run_rake_in_sandbox "$sandbox" "sops:init" "NON_INTERACTIVE=1" >/dev/null 2>&1
  
  # Verify credentials file exists after init
  assert_file_exists "credentials.yaml.enc exists after init" \
    "${sandbox}/config/credentials.yaml.enc"
  
  # Verify sops:edit task is available (check rake -T)
  local tasks_output
  tasks_output=$(
    export SOPS_AGE_KEY_FILE="${sandbox}/.config/sops/age/keys.txt"
    export HOME="${sandbox}"
    cd "$sandbox"
    bundle exec rake -T 2>&1
  )
  
  assert_output_contains "sops:edit task is available" \
    "sops:edit" echo "$tasks_output"
  
  assert_output_contains "sops:show task is available" \
    "sops:show" echo "$tasks_output"
  
  assert_output_contains "sops:init task is available" \
    "sops:init" echo "$tasks_output"
  
  cleanup_sandbox "sops_edit_task"
}

# Test: Full cycle - init, show (verify default content)
test_full_cycle() {
  log_section "Test: Full cycle (init → show default content)"
  
  local sandbox
  sandbox=$(setup_sandbox "full_cycle")
  
  # Step 1: Initialize - this creates default credentials
  log_info "Step 1: Initialize project"
  assert_success "sops:init succeeds" \
    run_rake_in_sandbox "$sandbox" "sops:init" "NON_INTERACTIVE=1"
  
  # Step 2: Verify the initialized file exists and has correct structure
  log_info "Step 2: Verify credentials file"
  assert_file_exists "credentials.yaml.enc exists" \
    "${sandbox}/config/credentials.yaml.enc"
  
  # Step 3: Show decrypted content (default template)
  log_info "Step 3: Verify decrypted content"
  local show_output
  show_output=$(run_rake_in_sandbox "$sandbox" "sops:show" 2>&1)
  
  # Default template should contain these (from init.rb CREDENTIALS_TEMPLATE)
  assert_output_contains "sops:show displays aws section" \
    "aws:" echo "$show_output"
  
  assert_output_contains "sops:show displays database section" \
    "database:" echo "$show_output"
  
  cleanup_sandbox "full_cycle"
}

# Test: Environment-specific credentials (RAILS_ENV)
# Note: This test verifies that RAILS_ENV affects file selection,
# even if the file doesn't exist (should report appropriate error)
test_environment_specific_credentials() {
  log_section "Test: Environment-specific credentials (RAILS_ENV)"
  
  local sandbox
  sandbox=$(setup_sandbox "env_specific")
  
  # Initialize (creates base credentials)
  run_rake_in_sandbox "$sandbox" "sops:init" "NON_INTERACTIVE=1" >/dev/null 2>&1
  
  # Without RAILS_ENV, show works on base credentials
  local base_output
  base_output=$(run_rake_in_sandbox "$sandbox" "sops:show" 2>&1)
  assert_output_contains "Base credentials work" "aws:" echo "$base_output"
  
  # With RAILS_ENV=production, it tries to find production credentials
  # Since they don't exist, it should fail with appropriate message
  local prod_output
  prod_output=$(RAILS_ENV=production run_rake_in_sandbox "$sandbox" "sops:show" 2>&1 || true)
  
  # Should mention the production file
  assert_output_contains "RAILS_ENV affects file selection" \
    "production" echo "$prod_output"
  
  cleanup_sandbox "env_specific"
}

# Test: SOPS_AGE_KEY environment variable (inline key)
# This test verifies that credentials can be decrypted using SOPS_AGE_KEY env var
test_sops_age_key_env() {
  log_section "Test: SOPS_AGE_KEY environment variable"
  
  local sandbox
  sandbox=$(setup_sandbox "age_key_env")
  
  # Initialize with standard key file
  run_rake_in_sandbox "$sandbox" "sops:init" "NON_INTERACTIVE=1" >/dev/null 2>&1
  
  # First verify normal decryption works
  local normal_output
  normal_output=$(run_rake_in_sandbox "$sandbox" "sops:show" 2>&1)
  assert_output_contains "Normal decryption works" "aws:" echo "$normal_output"
  
  # Extract the private key from the key file
  local keys_file="${sandbox}/.config/sops/age/keys.txt"
  local private_key
  private_key=$(grep "^AGE-SECRET-KEY" "$keys_file")
  
  # Remove the key file to force use of SOPS_AGE_KEY
  rm -f "$keys_file"
  
  # Set SOPS_AGE_KEY and try to decrypt
  local env_key_output
  env_key_output=$(
    export SOPS_AGE_KEY="$private_key"
    unset SOPS_AGE_KEY_FILE
    export HOME="${sandbox}"
    cd "$sandbox"
    bundle exec rake sops:show 2>&1
  )
  
  # Should be able to decrypt with inline key
  assert_output_contains "SOPS_AGE_KEY env var allows decryption" \
    "aws:" echo "$env_key_output"
  
  cleanup_sandbox "age_key_env"
}

# Test: Debug mode output
test_debug_mode() {
  log_section "Test: Debug mode (SOPS_RAILS_DEBUG=1)"
  
  local sandbox
  sandbox=$(setup_sandbox "debug_mode")
  
  # Initialize
  run_rake_in_sandbox "$sandbox" "sops:init" "NON_INTERACTIVE=1" >/dev/null 2>&1
  
  # Run with debug mode enabled
  local show_output
  export SOPS_RAILS_DEBUG=1
  show_output=$(run_rake_in_sandbox "$sandbox" "sops:show" 2>&1)
  unset SOPS_RAILS_DEBUG
  
  # Debug output should contain key info
  assert_output_contains "Debug mode shows sops_rails prefix" \
    "sops_rails" echo "$show_output"
  
  cleanup_sandbox "debug_mode"
}

# Test: Re-initialization (idempotent)
test_reinit_idempotent() {
  log_section "Test: Re-initialization is safe"
  
  local sandbox
  sandbox=$(setup_sandbox "reinit")
  
  # Initialize twice
  run_rake_in_sandbox "$sandbox" "sops:init" "NON_INTERACTIVE=1" >/dev/null 2>&1
  
  # Capture first state
  local first_sops_yaml
  first_sops_yaml=$(cat "${sandbox}/.sops.yaml")
  
  # Run init again
  assert_success "Second sops:init succeeds" \
    run_rake_in_sandbox "$sandbox" "sops:init" "NON_INTERACTIVE=1"
  
  # Files should still exist and be valid
  assert_file_exists ".sops.yaml still exists" "${sandbox}/.sops.yaml"
  assert_file_exists "credentials still exists" "${sandbox}/config/credentials.yaml.enc"
  
  # Content should be viewable
  local show_output
  show_output=$(run_rake_in_sandbox "$sandbox" "sops:show" 2>&1)
  assert_output_contains "Can still view credentials after re-init" \
    "aws:" echo "$show_output"
  
  cleanup_sandbox "reinit"
}

# Test: Invalid encrypted file
test_invalid_encrypted_file() {
  log_section "Test: Invalid encrypted file handling"
  
  local sandbox
  sandbox=$(setup_sandbox "invalid_file")
  
  # Create minimal setup
  local public_key
  public_key=$(generate_sandbox_age_key "$sandbox")
  
  cat > "${sandbox}/.sops.yaml" << EOF
creation_rules:
  - path_regex: .*\.yaml\.enc$
    age:
      - ${public_key}
EOF

  # Create Gemfile and Rakefile
  cat > "${sandbox}/Gemfile" << EOF
source "https://rubygems.org"
gem "sops_rails", path: "${GEM_ROOT}"
gem "rake"
EOF

  cat > "${sandbox}/Rakefile" << 'EOF'
require "bundler/setup"
require "sops_rails"
load "sops_rails/tasks/sops.rake"
EOF

  # Create invalid encrypted file
  mkdir -p "${sandbox}/config"
  echo "not: valid: encrypted: content" > "${sandbox}/config/credentials.yaml.enc"
  
  # sops:show should fail gracefully
  assert_failure "sops:show fails for invalid encrypted file" \
    run_rake_in_sandbox "$sandbox" "sops:show"
  
  cleanup_sandbox "invalid_file"
}

# Test: Credentials file content verification
# This test verifies the decrypted content structure is valid YAML
test_credentials_structure() {
  log_section "Test: Credentials structure validation"
  
  local sandbox
  sandbox=$(setup_sandbox "creds_structure")
  
  # Initialize
  run_rake_in_sandbox "$sandbox" "sops:init" "NON_INTERACTIVE=1" >/dev/null 2>&1
  
  # Get decrypted content
  local show_output
  show_output=$(run_rake_in_sandbox "$sandbox" "sops:show" 2>&1)
  
  # Verify it's valid YAML structure (has expected keys from template)
  assert_output_contains "Contains aws section" "aws:" echo "$show_output"
  assert_output_contains "Contains access_key_id" "access_key_id" echo "$show_output"
  assert_output_contains "Contains database section" "database:" echo "$show_output"
  assert_output_contains "Contains password field" "password" echo "$show_output"
  
  # Verify output is not empty
  assert_not_empty "Output is not empty" "$show_output"
  
  cleanup_sandbox "creds_structure"
}

# ==============================================================================
# Main Test Runner
# ==============================================================================

run_all_tests() {
  log_header "sops_rails Integration Test Suite"
  echo ""
  log_info "Gem root: ${GEM_ROOT}"
  log_info "Sandbox dir: ${SANDBOX_DIR}"
  log_info "Verbose: ${VERBOSE}"
  log_info "Keep sandbox: ${KEEP_SANDBOX}"
  
  # Check prerequisites first
  if ! check_prerequisites; then
    return 2
  fi
  
  # Create sandbox directory
  mkdir -p "$SANDBOX_DIR"
  
  # Run test scenarios
  log_header "Running Test Scenarios"
  
  # Core functionality tests
  test_basic_init || true
  test_sops_show || true
  test_sops_show_with_file_path || true
  test_sops_show_nonexistent_file || true
  test_sops_edit_task || true
  test_full_cycle || true
  
  # Environment tests
  test_environment_specific_credentials || true
  test_sops_age_key_env || true
  test_debug_mode || true
  
  # Edge cases
  test_reinit_idempotent || true
  test_invalid_encrypted_file || true
  test_credentials_structure || true
  
  # Cleanup
  cleanup_all_sandboxes
  
  # Summary
  log_header "Test Summary"
  echo ""
  echo -e "  ${BOLD}Tests Run:${NC}    ${TESTS_RUN}"
  echo -e "  ${GREEN}Passed:${NC}       ${TESTS_PASSED}"
  echo -e "  ${RED}Failed:${NC}       ${TESTS_FAILED}"
  echo ""
  
  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}✓ All tests passed!${NC}"
    return 0
  else
    echo -e "${RED}${BOLD}✗ ${TESTS_FAILED} test(s) failed${NC}"
    return 1
  fi
}

# ==============================================================================
# CLI Argument Parsing
# ==============================================================================

show_help() {
  cat << EOF
sops_rails Integration Test Suite

Usage: $(basename "$0") [OPTIONS]

Options:
  -v, --verbose       Show detailed output for all tests
  -k, --keep-sandbox  Don't clean up sandbox directories after tests
  -h, --help          Show this help message

Environment Variables:
  VERBOSE=true        Same as --verbose
  KEEP_SANDBOX=true   Same as --keep-sandbox

Examples:
  $(basename "$0")                  # Run all tests
  $(basename "$0") --verbose        # Run with detailed output
  $(basename "$0") --keep-sandbox   # Keep sandbox for inspection

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -k|--keep-sandbox)
      KEEP_SANDBOX=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

# Run tests
run_all_tests
exit $?
