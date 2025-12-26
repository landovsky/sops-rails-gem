#!/usr/bin/env bash
#
# Key Management Scenario: Test age key handling
#
# Tests various key configuration scenarios:
# - SOPS_AGE_KEY environment variable
# - SOPS_AGE_KEY_FILE environment variable
# - Default key file location
# - Key file with multiple keys
#
# Usage:
#   ./test/integration/scenarios/key_management.sh
#   ./test/integration/scenarios/key_management.sh --verbose
#
# ------------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/sandbox.sh"

SCENARIO_NAME="key_management"
VERBOSE="${VERBOSE:-false}"

# Colors
if [[ -t 1 ]]; then
  BOLD='\033[1m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  BOLD=''
  BLUE=''
  NC=''
fi

log_section() {
  echo ""
  echo -e "${BLUE}──────────────────────────────────────────────────────────────${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}──────────────────────────────────────────────────────────────${NC}"
}

# ==============================================================================
# Key Management Tests
# ==============================================================================

test_sops_age_key_env_variable() {
  log_section "SOPS_AGE_KEY Environment Variable"
  
  local sandbox
  sandbox=$(create_sandbox "age_key_env")
  
  # Generate key
  local public_key private_key
  public_key=$(generate_age_key "$sandbox")
  private_key=$(get_private_key "$sandbox")
  
  create_sops_config "$sandbox" "$public_key"
  
  # Create encrypted content
  local content="inline_key_secret: value123"
  create_encrypted_credentials "$sandbox" "$content"
  
  # Remove the key file to ensure we use env var
  rm "$(get_keys_file "$sandbox")"
  
  # Try decryption using SOPS_AGE_KEY env var
  local show_output
  show_output=$(
    export SOPS_AGE_KEY="$private_key"
    unset SOPS_AGE_KEY_FILE
    export HOME="${sandbox}"
    cd "$sandbox"
    bundle exec rake sops:show 2>&1
  )
  
  assert_output_contains "SOPS_AGE_KEY env var works" "value123" echo "$show_output"
  
  destroy_sandbox "age_key_env"
}

test_sops_age_key_file_env_variable() {
  log_section "SOPS_AGE_KEY_FILE Environment Variable"
  
  local sandbox
  sandbox=$(create_sandbox "age_key_file_env")
  
  local public_key
  public_key=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key"
  
  # Create encrypted content
  local content="key_file_secret: filevalue456"
  create_encrypted_credentials "$sandbox" "$content"
  
  # Move key file to non-standard location
  local custom_key_path="${sandbox}/custom_keys/my_age_key.txt"
  mkdir -p "$(dirname "$custom_key_path")"
  mv "$(get_keys_file "$sandbox")" "$custom_key_path"
  
  # Try decryption using SOPS_AGE_KEY_FILE pointing to custom location
  local show_output
  show_output=$(
    export SOPS_AGE_KEY_FILE="$custom_key_path"
    export HOME="${sandbox}"
    cd "$sandbox"
    bundle exec rake sops:show 2>&1
  )
  
  assert_output_contains "SOPS_AGE_KEY_FILE env var works" "filevalue456" echo "$show_output"
  
  destroy_sandbox "age_key_file_env"
}

test_default_key_location() {
  log_section "Default Key Location (~/.config/sops/age/keys.txt)"
  
  local sandbox
  sandbox=$(create_sandbox "default_key_loc")
  
  local public_key
  public_key=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key"
  
  # Create encrypted content
  local content="default_loc_secret: defaultvalue789"
  create_encrypted_credentials "$sandbox" "$content"
  
  # Clear env vars and use HOME to set default location
  local show_output
  show_output=$(
    unset SOPS_AGE_KEY
    unset SOPS_AGE_KEY_FILE
    export HOME="${sandbox}"
    cd "$sandbox"
    bundle exec rake sops:show 2>&1
  )
  
  assert_output_contains "Default key location works" "defaultvalue789" echo "$show_output"
  
  destroy_sandbox "default_key_loc"
}

test_key_precedence() {
  log_section "Key Precedence (env var over file)"
  
  local sandbox
  sandbox=$(create_sandbox "key_precedence")
  
  # Generate first key and create encrypted content
  local public_key1 private_key1
  public_key1=$(generate_age_key "$sandbox")
  private_key1=$(get_private_key "$sandbox")
  
  create_sops_config "$sandbox" "$public_key1"
  
  local content="precedence_secret: key1_encrypted"
  create_encrypted_credentials "$sandbox" "$content"
  
  # Generate second key (different)
  rm "$(get_keys_file "$sandbox")"
  local public_key2
  public_key2=$(generate_age_key "$sandbox")
  
  # The file now has key2, but we'll set SOPS_AGE_KEY to key1
  # Decryption should work with key1 (env var takes precedence)
  local show_output
  show_output=$(
    export SOPS_AGE_KEY="$private_key1"
    export HOME="${sandbox}"
    cd "$sandbox"
    bundle exec rake sops:show 2>&1
  )
  
  assert_output_contains "SOPS_AGE_KEY takes precedence over file" "key1_encrypted" echo "$show_output"
  
  destroy_sandbox "key_precedence"
}

test_multiple_keys_in_file() {
  log_section "Multiple Keys in Key File"
  
  local sandbox
  sandbox=$(create_sandbox "multi_key")
  
  # Generate two keys
  local keys_file="${sandbox}/.config/sops/age/keys.txt"
  mkdir -p "$(dirname "$keys_file")"
  
  # Generate first key
  age-keygen >> "$keys_file" 2>/dev/null
  local public_key1
  public_key1=$(grep "public key:" "$keys_file" | head -1 | cut -d: -f2 | tr -d ' ')
  
  # Generate second key (append)
  echo "" >> "$keys_file"
  age-keygen >> "$keys_file" 2>/dev/null
  local public_key2
  public_key2=$(grep "public key:" "$keys_file" | tail -1 | cut -d: -f2 | tr -d ' ')
  
  # Create .sops.yaml with second key
  create_sops_config "$sandbox" "$public_key2"
  
  # Create encrypted content with second key
  local content="multi_key_secret: encrypted_with_key2"
  export SOPS_AGE_KEY_FILE="$keys_file"
  echo "$content" | sops --encrypt \
    --age "$public_key2" \
    --input-type yaml \
    --output-type yaml \
    /dev/stdin > "${sandbox}/config/credentials.yaml.enc"
  
  # Decryption should work (file contains both keys)
  local show_output
  show_output=$(run_rake "$sandbox" "sops:show" 2>&1)
  
  assert_output_contains "Multi-key file works" "encrypted_with_key2" echo "$show_output"
  
  destroy_sandbox "multi_key"
}

test_key_rotation_simulation() {
  log_section "Key Rotation Simulation"
  
  local sandbox
  sandbox=$(create_sandbox "key_rotation")
  
  # Generate initial key
  local public_key1
  public_key1=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key1"
  
  # Create initial encrypted content
  local initial_content="rotation_secret: initial_value"
  create_encrypted_credentials "$sandbox" "$initial_content"
  
  # Verify initial decryption works
  local show1
  show1=$(run_rake "$sandbox" "sops:show" 2>&1)
  assert_output_contains "Initial decryption works" "initial_value" echo "$show1"
  
  # Generate new key (simulating rotation)
  local keys_file
  keys_file=$(get_keys_file "$sandbox")
  local old_private_key
  old_private_key=$(get_private_key "$sandbox")
  
  # Add new key to file
  echo "" >> "$keys_file"
  age-keygen >> "$keys_file" 2>/dev/null
  local public_key2
  public_key2=$(grep "public key:" "$keys_file" | tail -1 | cut -d: -f2 | tr -d ' ')
  
  # Update .sops.yaml to include both keys
  cat > "${sandbox}/.sops.yaml" << EOF
creation_rules:
  - path_regex: config/credentials.*\\.yaml\\.enc\$
    age:
      - ${public_key1}
      - ${public_key2}
EOF

  # Re-encrypt with new key configuration (both keys)
  export SOPS_AGE_KEY_FILE="$keys_file"
  cd "$sandbox"
  sops updatekeys --yes config/credentials.yaml.enc 2>/dev/null || true
  
  # Should still be able to decrypt
  local show2
  show2=$(run_rake "$sandbox" "sops:show" 2>&1)
  assert_output_contains "Decryption works after key rotation" "initial_value" echo "$show2"
  
  destroy_sandbox "key_rotation"
}

test_debug_shows_key_info() {
  log_section "Debug Mode Shows Key Information"
  
  local sandbox
  sandbox=$(create_initialized_sandbox "debug_key_info")
  
  # Run with debug mode
  local debug_output
  debug_output=$(
    export SOPS_RAILS_DEBUG=1
    run_rake "$sandbox" "sops:show" 2>&1
  )
  
  # Debug output should show key-related info
  assert_output_contains "Debug shows sops_rails prefix" "sops_rails" echo "$debug_output"
  
  destroy_sandbox "debug_key_info"
}

test_public_key_in_sops_yaml() {
  log_section "Public Key Correctly Set in .sops.yaml"
  
  local sandbox
  sandbox=$(create_sandbox "public_key_check")
  
  # Run init
  run_rake "$sandbox" "sops:init" "NON_INTERACTIVE=1" >/dev/null 2>&1
  
  # Get the public key
  local public_key
  public_key=$(get_public_key "$sandbox")
  
  # Verify .sops.yaml contains the public key
  assert_file_contains ".sops.yaml has public key" "${sandbox}/.sops.yaml" "$public_key"
  
  # Verify key format is valid (starts with age1)
  assert_matches "Public key has correct format" "$public_key" "^age1[a-z0-9]+"
  
  destroy_sandbox "public_key_check"
}

# ==============================================================================
# Main Runner
# ==============================================================================

run_scenario() {
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  Scenario: ${SCENARIO_NAME}${NC}"
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
  
  # Run test cases
  test_sops_age_key_env_variable || true
  test_sops_age_key_file_env_variable || true
  test_default_key_location || true
  test_key_precedence || true
  test_multiple_keys_in_file || true
  test_key_rotation_simulation || true
  test_debug_shows_key_info || true
  test_public_key_in_sops_yaml || true
  
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
