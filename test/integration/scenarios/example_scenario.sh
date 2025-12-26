#!/usr/bin/env bash
#
# Example Scenario: Custom Credentials Workflow
#
# This file demonstrates how to create a new test scenario.
# Copy this template and modify for your specific test case.
#
# Usage:
#   ./test/integration/scenarios/example_scenario.sh
#   ./test/integration/scenarios/example_scenario.sh --verbose
#
# ------------------------------------------------------------------------------

set -euo pipefail

# Locate libraries relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source helper libraries
source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/sandbox.sh"

# ==============================================================================
# Configuration
# ==============================================================================

SCENARIO_NAME="example_custom_workflow"
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

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

# ==============================================================================
# Test Cases
# ==============================================================================

test_custom_credentials_structure() {
  log_section "Custom Credentials Structure"
  
  local sandbox
  sandbox=$(create_sandbox "custom_structure")
  
  # Generate age key and setup
  local public_key
  public_key=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key"
  
  # Create credentials with custom structure
  local custom_content="
services:
  stripe:
    api_key: sk_test_custom123
    webhook_secret: whsec_custom456
  
  twilio:
    account_sid: AC_custom789
    auth_token: auth_custom000

infrastructure:
  database:
    host: db.example.com
    port: 5432
    username: app_user
    password: super_secret_password
  
  redis:
    url: redis://localhost:6379/0
"
  
  create_encrypted_credentials "$sandbox" "$custom_content"
  
  # Verify structure is preserved after decryption
  local show_output
  show_output=$(run_rake "$sandbox" "sops:show" 2>&1)
  
  assert_output_contains "Services section exists" "services:" echo "$show_output"
  assert_output_contains "Stripe config exists" "sk_test_custom123" echo "$show_output"
  assert_output_contains "Twilio config exists" "AC_custom789" echo "$show_output"
  assert_output_contains "Infrastructure section exists" "infrastructure:" echo "$show_output"
  assert_output_contains "Database password preserved" "super_secret_password" echo "$show_output"
  
  destroy_sandbox "custom_structure"
}

test_multiple_environments() {
  log_section "Multiple Environment Files"
  
  local sandbox
  sandbox=$(create_sandbox "multi_env")
  
  local public_key
  public_key=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key"
  
  # Create base credentials
  local base_content="
api_url: https://api.example.com
debug: false
timeout: 30
"
  create_encrypted_credentials "$sandbox" "$base_content" "credentials.yaml.enc"
  
  # Create development credentials
  local dev_content="
api_url: http://localhost:3000
debug: true
timeout: 60
"
  create_encrypted_credentials "$sandbox" "$dev_content" "credentials.development.yaml.enc"
  
  # Create production credentials
  local prod_content="
api_url: https://production.example.com
debug: false
timeout: 10
secret_key: production_only_secret
"
  create_encrypted_credentials "$sandbox" "$prod_content" "credentials.production.yaml.enc"
  
  # Verify each file separately
  local base_output dev_output prod_output
  
  base_output=$(run_rake "$sandbox" "sops:show[config/credentials.yaml.enc]" 2>&1)
  assert_output_contains "Base file shows api.example.com" "api.example.com" echo "$base_output"
  
  dev_output=$(run_rake "$sandbox" "sops:show[config/credentials.development.yaml.enc]" 2>&1)
  assert_output_contains "Dev file shows localhost" "localhost:3000" echo "$dev_output"
  
  prod_output=$(run_rake "$sandbox" "sops:show[config/credentials.production.yaml.enc]" 2>&1)
  assert_output_contains "Prod file shows production URL" "production.example.com" echo "$prod_output"
  assert_output_contains "Prod has secret_key" "production_only_secret" echo "$prod_output"
  
  destroy_sandbox "multi_env"
}

test_special_characters_in_values() {
  log_section "Special Characters in Values"
  
  local sandbox
  sandbox=$(create_sandbox "special_chars")
  
  local public_key
  public_key=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key"
  
  # Create credentials with special characters
  # Note: Some characters need careful escaping
  local special_content='
passwords:
  with_quotes: "has \"quotes\" inside"
  with_newlines: "line1\nline2"
  with_special: "!@#$%^&*()_+-=[]{}|;:,.<>?"
  with_unicode: "こんにちは"
  with_emoji: "🔐🔑"
urls:
  with_query: "https://api.example.com/path?key=value&other=123"
  with_hash: "redis://user:p@ss#word@localhost/0"
'
  
  create_encrypted_credentials "$sandbox" "$special_content"
  
  local show_output
  show_output=$(run_rake "$sandbox" "sops:show" 2>&1)
  
  assert_output_contains "Quotes preserved" 'quotes' echo "$show_output"
  assert_output_contains "Special chars preserved" '!@#' echo "$show_output"
  assert_output_contains "URLs preserved" 'api.example.com' echo "$show_output"
  
  destroy_sandbox "special_chars"
}

# ==============================================================================
# Main Runner
# ==============================================================================

run_scenario() {
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  Scenario: ${SCENARIO_NAME}${NC}"
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════════${NC}"
  
  # Run test cases
  test_custom_credentials_structure || true
  test_multiple_environments || true
  test_special_characters_in_values || true
  
  # Print summary
  print_test_summary
}

# ==============================================================================
# CLI
# ==============================================================================

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
