#!/usr/bin/env bash
#
# Sandbox Management Library for sops_rails Integration Tests
#
# Provides functions to create isolated test environments with their own
# age keys, configuration, and gem setup.
#
# Usage:
#   source "$(dirname "$0")/lib/sandbox.sh"
#   sandbox=$(create_sandbox "my_test")
#   # ... run tests ...
#   destroy_sandbox "my_test"
#
# ------------------------------------------------------------------------------

# Default paths (can be overridden before sourcing)
: "${SANDBOX_BASE_DIR:=$(dirname "${BASH_SOURCE[0]}")/../sandbox}"
: "${GEM_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

# ==============================================================================
# Sandbox Creation & Destruction
# ==============================================================================

# Create a new isolated sandbox environment
# Usage: sandbox_path=$(create_sandbox "name")
create_sandbox() {
  local name="${1:-$(date +%s)}"
  local sandbox_path="${SANDBOX_BASE_DIR}/${name}"
  
  # Clean up existing sandbox
  rm -rf "$sandbox_path"
  mkdir -p "$sandbox_path"
  mkdir -p "${sandbox_path}/.config/sops/age"
  mkdir -p "${sandbox_path}/config"
  
  # Create minimal Gemfile
  cat > "${sandbox_path}/Gemfile" << EOF
source "https://rubygems.org"
gem "sops_rails", path: "${GEM_ROOT}"
gem "rake"
EOF

  # Create Rakefile
  cat > "${sandbox_path}/Rakefile" << 'EOF'
require "bundler/setup"
require "sops_rails"
load "sops_rails/tasks/sops.rake"
EOF

  echo "$sandbox_path"
}

# Destroy a sandbox and clean up
# Usage: destroy_sandbox "name"
destroy_sandbox() {
  local name="$1"
  local sandbox_path="${SANDBOX_BASE_DIR}/${name}"
  rm -rf "$sandbox_path"
}

# Destroy all sandboxes
# Usage: destroy_all_sandboxes
destroy_all_sandboxes() {
  rm -rf "$SANDBOX_BASE_DIR"
}

# ==============================================================================
# Age Key Management
# ==============================================================================

# Generate an age key for the sandbox
# Usage: public_key=$(generate_age_key "$sandbox_path")
generate_age_key() {
  local sandbox_path="$1"
  local keys_file="${sandbox_path}/.config/sops/age/keys.txt"
  
  mkdir -p "$(dirname "$keys_file")"
  age-keygen -o "$keys_file" 2>/dev/null
  
  # Return public key
  grep "public key:" "$keys_file" | cut -d: -f2 | tr -d ' '
}

# Get public key from sandbox
# Usage: public_key=$(get_public_key "$sandbox_path")
get_public_key() {
  local sandbox_path="$1"
  local keys_file="${sandbox_path}/.config/sops/age/keys.txt"
  
  if [[ -f "$keys_file" ]]; then
    grep "public key:" "$keys_file" | cut -d: -f2 | tr -d ' '
  fi
}

# Get private key from sandbox
# Usage: private_key=$(get_private_key "$sandbox_path")
get_private_key() {
  local sandbox_path="$1"
  local keys_file="${sandbox_path}/.config/sops/age/keys.txt"
  
  if [[ -f "$keys_file" ]]; then
    grep "^AGE-SECRET-KEY" "$keys_file"
  fi
}

# Get keys file path
# Usage: keys_file=$(get_keys_file "$sandbox_path")
get_keys_file() {
  local sandbox_path="$1"
  echo "${sandbox_path}/.config/sops/age/keys.txt"
}

# ==============================================================================
# SOPS Configuration
# ==============================================================================

# Create .sops.yaml with given public key
# Usage: create_sops_config "$sandbox_path" "$public_key"
create_sops_config() {
  local sandbox_path="$1"
  local public_key="$2"
  
  cat > "${sandbox_path}/.sops.yaml" << EOF
creation_rules:
  - path_regex: config/credentials(\\..*)?\\.yaml\\.enc\$
    age: ${public_key}
  - path_regex: \\.env(\\..*)?\\.enc\$
    age: ${public_key}
  - path_regex: .*
    age: ""
EOF
}

# ==============================================================================
# Encrypted Content Creation
# ==============================================================================

# Create encrypted credentials file
# Usage: create_encrypted_credentials "$sandbox_path" "$content"
create_encrypted_credentials() {
  local sandbox_path="$1"
  local content="$2"
  local file_name="${3:-credentials.yaml.enc}"
  local public_key
  public_key=$(get_public_key "$sandbox_path")
  
  export SOPS_AGE_KEY_FILE="$(get_keys_file "$sandbox_path")"
  
  echo "$content" | sops --encrypt \
    --age "$public_key" \
    --input-type yaml \
    --output-type yaml \
    /dev/stdin > "${sandbox_path}/config/${file_name}"
}

# Create encrypted env file
# Usage: create_encrypted_env "$sandbox_path" "$content" ".env.enc"
create_encrypted_env() {
  local sandbox_path="$1"
  local content="$2"
  local file_name="${3:-.env.enc}"
  local public_key
  public_key=$(get_public_key "$sandbox_path")
  
  export SOPS_AGE_KEY_FILE="$(get_keys_file "$sandbox_path")"
  
  echo "$content" | sops --encrypt \
    --age "$public_key" \
    --input-type dotenv \
    --output-type dotenv \
    /dev/stdin > "${sandbox_path}/${file_name}"
}

# ==============================================================================
# Command Execution
# ==============================================================================

# Run command in sandbox with proper environment
# Usage: run_in_sandbox "$sandbox_path" command [args...]
run_in_sandbox() {
  local sandbox_path="$1"
  shift
  
  (
    export SOPS_AGE_KEY_FILE="$(get_keys_file "$sandbox_path")"
    export HOME="${sandbox_path}"
    cd "$sandbox_path"
    "$@"
  )
}

# Run rake task in sandbox
# Usage: run_rake "$sandbox_path" "task_name" [extra_args...]
run_rake() {
  local sandbox_path="$1"
  local task="$2"
  shift 2
  
  (
    export SOPS_AGE_KEY_FILE="$(get_keys_file "$sandbox_path")"
    export HOME="${sandbox_path}"
    cd "$sandbox_path"
    bundle install --quiet 2>/dev/null || bundle install
    bundle exec rake "$task" "$@"
  )
}

# Run rake with specific environment
# Usage: run_rake_with_env "$sandbox_path" "task" "VAR=value" [more_vars...]
run_rake_with_env() {
  local sandbox_path="$1"
  local task="$2"
  shift 2
  
  (
    export SOPS_AGE_KEY_FILE="$(get_keys_file "$sandbox_path")"
    export HOME="${sandbox_path}"
    cd "$sandbox_path"
    
    # Set additional environment variables
    for var in "$@"; do
      export "$var"
    done
    
    bundle install --quiet 2>/dev/null || bundle install
    bundle exec rake "$task"
  )
}

# ==============================================================================
# Setup Helpers
# ==============================================================================

# Initialize sandbox with sops:init
# Usage: init_sandbox "$sandbox_path"
init_sandbox() {
  local sandbox_path="$1"
  run_rake "$sandbox_path" "sops:init" "NON_INTERACTIVE=1" >/dev/null 2>&1
}

# Create fully initialized sandbox ready for testing
# Usage: sandbox=$(create_initialized_sandbox "name")
create_initialized_sandbox() {
  local name="$1"
  local sandbox_path
  sandbox_path=$(create_sandbox "$name")
  init_sandbox "$sandbox_path"
  echo "$sandbox_path"
}

# Create sandbox with custom credentials
# Usage: sandbox=$(create_sandbox_with_creds "name" "yaml_content")
create_sandbox_with_creds() {
  local name="$1"
  local content="$2"
  local sandbox_path
  sandbox_path=$(create_sandbox "$name")
  
  local public_key
  public_key=$(generate_age_key "$sandbox_path")
  create_sops_config "$sandbox_path" "$public_key"
  create_encrypted_credentials "$sandbox_path" "$content"
  
  echo "$sandbox_path"
}
