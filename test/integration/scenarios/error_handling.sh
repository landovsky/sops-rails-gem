#!/usr/bin/env bash
#
# Error Handling Scenario: Test error conditions and edge cases
#
# This scenario tests how sops_rails handles various error conditions:
# - Missing files
# - Invalid encrypted content
# - Wrong keys
# - Missing binaries (simulated)
#
# Usage:
#   ./test/integration/scenarios/error_handling.sh
#   ./test/integration/scenarios/error_handling.sh --verbose
#
# ------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/sandbox.sh"

SCENARIO_NAME="error_handling"
VERBOSE="${VERBOSE:-false}"

# Colors
if [[ -t 1 ]]; then
  BOLD='\033[1m'
  BLUE='\033[0;34m'
  RED='\033[0;31m'
  NC='\033[0m'
else
  BOLD=''
  BLUE=''
  RED=''
  NC=''
fi

log_section() {
  echo ""
  echo -e "${BLUE}──────────────────────────────────────────────────────────────${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}──────────────────────────────────────────────────────────────${NC}"
}

# ==============================================================================
# Error Condition Tests
# ==============================================================================

test_missing_credentials_file() {
  log_section "Error: Missing Credentials File"
  
  local sandbox
  sandbox=$(create_sandbox "missing_file")
  
  local public_key
  public_key=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key"
  
  # Don't create credentials file
  
  # sops:show should fail gracefully
  assert_failure "sops:show fails for missing file" \
    run_rake "$sandbox" "sops:show"
  
  # Error message should be helpful
  local error_output
  error_output=$(run_rake "$sandbox" "sops:show" 2>&1 || true)
  assert_contains "Error mentions file not found" "$error_output" "not found"
  
  destroy_sandbox "missing_file"
}

test_invalid_yaml_structure() {
  log_section "Error: Invalid YAML in Encrypted File"
  
  local sandbox
  sandbox=$(create_sandbox "invalid_yaml")
  
  local public_key
  public_key=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key"
  
  # Create file with invalid YAML (but valid SOPS encryption)
  # This tests the decryption succeeds but content is unusual
  local invalid_content="
key: value
  bad_indent: this is invalid
another: value
"
  
  # SOPS might actually handle this, so let's test corrupted file instead
  # Create a file that looks like SOPS but isn't valid
  mkdir -p "${sandbox}/config"
  echo "not: actually: sops: encrypted" > "${sandbox}/config/credentials.yaml.enc"
  
  # sops:show should fail
  assert_failure "sops:show fails for non-SOPS file" \
    run_rake "$sandbox" "sops:show"
  
  destroy_sandbox "invalid_yaml"
}

test_wrong_key() {
  log_section "Error: Wrong Decryption Key"
  
  local sandbox
  sandbox=$(create_sandbox "wrong_key")
  
  # Create credentials with one key
  local public_key1
  public_key1=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key1"
  
  local content="secret: encrypted_with_key1"
  create_encrypted_credentials "$sandbox" "$content"
  
  # Now generate a different key and try to decrypt
  rm "${sandbox}/.config/sops/age/keys.txt"
  generate_age_key "$sandbox" >/dev/null
  
  # sops:show should fail (wrong key)
  assert_failure "sops:show fails with wrong key" \
    run_rake "$sandbox" "sops:show"
  
  destroy_sandbox "wrong_key"
}

test_empty_credentials_file() {
  log_section "Error: Empty Credentials File"
  
  local sandbox
  sandbox=$(create_sandbox "empty_file")
  
  local public_key
  public_key=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key"
  
  # Create empty file
  mkdir -p "${sandbox}/config"
  touch "${sandbox}/config/credentials.yaml.enc"
  
  # sops:show should fail (empty file isn't valid SOPS)
  assert_failure "sops:show fails for empty file" \
    run_rake "$sandbox" "sops:show"
  
  destroy_sandbox "empty_file"
}

test_corrupted_sops_metadata() {
  log_section "Error: Corrupted SOPS Metadata"
  
  local sandbox
  sandbox=$(create_sandbox "corrupted_meta")
  
  local public_key
  public_key=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key"
  
  # Create valid encrypted file first
  local content="secret: value"
  create_encrypted_credentials "$sandbox" "$content"
  
  # Corrupt the SOPS metadata
  sed -i 's/sops:/CORRUPTED:/' "${sandbox}/config/credentials.yaml.enc" 2>/dev/null || \
    sed -i '' 's/sops:/CORRUPTED:/' "${sandbox}/config/credentials.yaml.enc"
  
  # sops:show should fail
  assert_failure "sops:show fails with corrupted metadata" \
    run_rake "$sandbox" "sops:show"
  
  destroy_sandbox "corrupted_meta"
}

test_missing_sops_yaml() {
  log_section "Warning: Missing .sops.yaml (for sops:edit on new file)"
  
  local sandbox
  sandbox=$(create_sandbox "no_sops_yaml")
  
  # Generate key but don't create .sops.yaml
  generate_age_key "$sandbox" >/dev/null
  
  # sops:init should work and create .sops.yaml
  assert_success "sops:init creates .sops.yaml" \
    run_rake "$sandbox" "sops:init" "NON_INTERACTIVE=1"
  
  assert_file_exists ".sops.yaml was created" "${sandbox}/.sops.yaml"
  
  destroy_sandbox "no_sops_yaml"
}

test_nonexistent_rails_env() {
  log_section "Error: Non-existent RAILS_ENV credentials"
  
  local sandbox
  sandbox=$(create_initialized_sandbox "bad_rails_env")
  
  # Try to show staging credentials that don't exist
  assert_failure "sops:show fails for missing env-specific file" \
    run_rake_with_env "$sandbox" "sops:show" "RAILS_ENV=staging"
  
  destroy_sandbox "bad_rails_env"
}

test_permission_denied() {
  log_section "Error: Permission Denied on Key File"
  
  # Skip if running as root
  if [[ $EUID -eq 0 ]]; then
    echo "[SKIP] Running as root, permission test skipped"
    return 0
  fi
  
  local sandbox
  sandbox=$(create_sandbox "permission_test")
  
  local public_key
  public_key=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key"
  
  local content="secret: value"
  create_encrypted_credentials "$sandbox" "$content"
  
  # Remove read permission from key file
  chmod 000 "${sandbox}/.config/sops/age/keys.txt"
  
  # sops:show should fail (can't read key)
  local result=0
  run_rake "$sandbox" "sops:show" 2>/dev/null || result=$?
  
  # Restore permissions for cleanup
  chmod 644 "${sandbox}/.config/sops/age/keys.txt"
  
  assert_not_equals "sops:show fails without key permissions" "0" "$result"
  
  destroy_sandbox "permission_test"
}

test_explicit_file_not_found_error_message() {
  log_section "Error Message Quality: File Not Found"
  
  local sandbox
  sandbox=$(create_initialized_sandbox "error_message_test")
  
  # Try to show a file that doesn't exist
  local error_output
  error_output=$(run_rake "$sandbox" "sops:show[config/nonexistent.yaml.enc]" 2>&1 || true)
  
  # Error should mention the file path
  assert_contains "Error mentions file path" "$error_output" "nonexistent.yaml.enc"
  
  # Error should be clear it's a "not found" type error
  assert_contains "Error indicates file not found" "$error_output" "not found\|does not exist\|No such file"
  
  destroy_sandbox "error_message_test"
}

test_binary_not_in_path() {
  log_section "Error: SOPS Binary Not Available (Simulated)"
  
  local sandbox
  sandbox=$(create_sandbox "no_binary")
  
  # Create a minimal setup
  local public_key
  public_key=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key"
  
  # Create credentials manually (bypassing binary check)
  mkdir -p "${sandbox}/config"
  echo "dummy: content" > "${sandbox}/config/credentials.yaml.enc"
  
  # Run with PATH that excludes sops
  local error_output
  error_output=$(
    export PATH="/usr/bin:/bin"  # Exclude typical sops locations
    export SOPS_AGE_KEY_FILE="$(get_keys_file "$sandbox")"
    export HOME="${sandbox}"
    cd "$sandbox"
    bundle exec rake sops:show 2>&1 || true
  )
  
  # Check if error mentions sops not found (if sops isn't in restricted PATH)
  if ! command -v sops &>/dev/null; then
    assert_contains "Error mentions sops not found" "$error_output" "sops.*not found\|SopsNotFoundError"
  else
    echo "[INFO] SOPS found in restricted PATH, skipping binary check test"
  fi
  
  destroy_sandbox "no_binary"
}

# ==============================================================================
# Main Runner
# ==============================================================================

run_scenario() {
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  Scenario: ${SCENARIO_NAME}${NC}"
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
  
  # Run test cases
  test_missing_credentials_file || true
  test_invalid_yaml_structure || true
  test_wrong_key || true
  test_empty_credentials_file || true
  test_corrupted_sops_metadata || true
  test_missing_sops_yaml || true
  test_nonexistent_rails_env || true
  test_permission_denied || true
  test_explicit_file_not_found_error_message || true
  test_binary_not_in_path || true
  
  # Print summary
  print_test_summary
}

# CLI
while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

run_scenario
