# sops_rails Integration Tests

This directory contains integration tests that verify the sops_rails gem works correctly with actual SOPS/age encryption.

## Prerequisites

Before running the tests, ensure you have:

- **SOPS** (v3.8.0+): `brew install sops` (macOS) or `apt install sops` (Debian/Ubuntu)
- **age** (v1.0.0+): `brew install age` (macOS) or `apt install age` (Debian/Ubuntu)
- **Ruby** (3.2.0+) with Bundler

## Quick Start

```bash
# Run all integration tests
./test/integration/run_integration_tests.sh

# Run with verbose output
./test/integration/run_integration_tests.sh --verbose

# Keep sandbox directories for inspection
./test/integration/run_integration_tests.sh --keep-sandbox
```

## Directory Structure

```
test/integration/
├── run_integration_tests.sh    # Main test runner
├── README.md                   # This file
├── lib/                        # Reusable libraries
│   ├── assertions.sh           # Assertion functions
│   └── sandbox.sh              # Sandbox management
├── scenarios/                  # Individual test scenarios
│   ├── example_scenario.sh     # Custom credentials workflow
│   ├── error_handling.sh       # Error condition tests
│   └── key_management.sh       # Age key handling tests
└── sandbox/                    # Temporary test directories (gitignored)
```

## Running Individual Scenarios

Each scenario can be run independently:

```bash
# Run specific scenario
./test/integration/scenarios/example_scenario.sh
./test/integration/scenarios/error_handling.sh --verbose
./test/integration/scenarios/key_management.sh
```

## Writing New Scenarios

### 1. Copy the Template

```bash
cp test/integration/scenarios/example_scenario.sh test/integration/scenarios/my_scenario.sh
chmod +x test/integration/scenarios/my_scenario.sh
```

### 2. Source the Libraries

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

source "${LIB_DIR}/assertions.sh"
source "${LIB_DIR}/sandbox.sh"
```

### 3. Write Test Functions

```bash
test_my_feature() {
  log_section "My Feature Test"
  
  # Create isolated sandbox
  local sandbox
  sandbox=$(create_sandbox "my_test")
  
  # Set up: generate key, create config, etc.
  local public_key
  public_key=$(generate_age_key "$sandbox")
  create_sops_config "$sandbox" "$public_key"
  
  # Create test content
  local content="my_key: my_value"
  create_encrypted_credentials "$sandbox" "$content"
  
  # Run assertions
  local output
  output=$(run_rake "$sandbox" "sops:show" 2>&1)
  assert_output_contains "Feature works" "my_value" echo "$output"
  
  # Clean up
  destroy_sandbox "my_test"
}
```

## Available Assertion Functions

### Command Assertions

```bash
# Command succeeds (exit 0)
assert_success "description" command [args...]

# Command fails (non-zero exit)
assert_failure "description" command [args...]

# Specific exit code
assert_exit_code "description" expected_code command [args...]
```

### Output Assertions

```bash
# Output contains string
assert_output_contains "description" "expected" command [args...]

# Output does not contain
assert_output_not_contains "description" "unexpected" command [args...]

# Output matches regex
assert_output_matches "description" "pattern" command [args...]
```

### String Assertions

```bash
# Strings equal
assert_equals "description" "expected" "actual"

# Strings not equal
assert_not_equals "description" "unexpected" "actual"

# String contains
assert_contains "description" "$haystack" "needle"

# String matches regex
assert_matches "description" "$string" "pattern"

# Not empty
assert_not_empty "description" "$value"
```

### File Assertions

```bash
# File exists
assert_file_exists "description" /path/to/file

# File does not exist
assert_file_not_exists "description" /path/to/file

# Directory exists
assert_dir_exists "description" /path/to/dir

# File contains string
assert_file_contains "description" /path/to/file "expected"

# File not empty
assert_file_not_empty "description" /path/to/file
```

## Sandbox Management

### Creating Sandboxes

```bash
# Basic sandbox
sandbox=$(create_sandbox "name")

# Pre-initialized sandbox (runs sops:init)
sandbox=$(create_initialized_sandbox "name")

# Sandbox with custom credentials
sandbox=$(create_sandbox_with_creds "name" "yaml_content")
```

### Key Management

```bash
# Generate age key
public_key=$(generate_age_key "$sandbox")

# Get existing public key
public_key=$(get_public_key "$sandbox")

# Get private key
private_key=$(get_private_key "$sandbox")

# Get key file path
keys_file=$(get_keys_file "$sandbox")
```

### Running Commands

```bash
# Run command in sandbox
run_in_sandbox "$sandbox" command [args...]

# Run rake task
run_rake "$sandbox" "task_name" [extra_args...]

# Run rake with environment variables
run_rake_with_env "$sandbox" "task" "VAR=value"
```

### Cleanup

```bash
# Destroy specific sandbox
destroy_sandbox "name"

# Destroy all sandboxes
destroy_all_sandboxes
```

## Test Output Format

Tests produce structured output that's easy to parse:

```
════════════════════════════════════════════════════════════════════════
  sops_rails Integration Test Suite
════════════════════════════════════════════════════════════════════════

[INFO] Gem root: /path/to/gem
[INFO] Checking prerequisites...

──────────────────────────────────────────────────────────────
  Test: Basic sops:init
──────────────────────────────────────────────────────────────

[PASS] sops:init completes successfully
[PASS] .sops.yaml was created
[PASS] credentials.yaml.enc was created

[FAIL] Some test that failed
[EXPECTED TO CONTAIN]
  │ expected string
[ACTUAL OUTPUT]
  │ actual output here

════════════════════════════════════════════════════════════════════════
  TEST SUMMARY
════════════════════════════════════════════════════════════════════════

  Tests Run:    15
  Passed:       14
  Failed:       1

✗ 1 test(s) failed
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `VERBOSE=true` | Show detailed output for all tests |
| `KEEP_SANDBOX=true` | Don't clean up sandbox directories |
| `SOPS_RAILS_DEBUG=1` | Enable debug mode in sops_rails |

## Troubleshooting

### Tests Hang

If tests hang, it's usually because:
- SOPS is prompting for input (check editor config)
- Bundle install is taking too long

### Permission Errors

Ensure you have write access to the test directory:
```bash
chmod -R u+rwX test/integration/
```

### SOPS Binary Issues

Verify SOPS is correctly installed:
```bash
sops --version
age --version
age-keygen --version
```

### Sandbox Cleanup Fails

If sandboxes don't clean up properly:
```bash
rm -rf test/integration/sandbox/
```
