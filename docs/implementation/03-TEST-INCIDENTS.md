# Test Incidents

This document tracks test-related incidents including critical tests that were missing and false positive tests, along with their mitigations.

## Incident: Binary.encrypt_to_file False Positive - Invalid SOPS Output

**Date**: 2024-12-27

**Type**: False Positive / Missing Integration Test

### Problem Summary

The `Binary.encrypt_to_file` method created files that SOPS could not edit, causing `sops:edit` to fail with "error emitting binary store: no binary data found in tree". All unit tests passed because they:

1. Mocked SOPS output with fake string `"sops_encrypted_content_here"`
2. Verified command arguments and file writes
3. Never verified the output could be read/edited by SOPS

The bug manifested when using the `sops:edit` rake task for environment-specific credentials:
```
sops -e --input-type yaml --age <key> /tmp/file > target.enc  # Created invalid output
sops --input-type yaml target.enc                              # Failed to parse
```

### Root Cause

**Implementation bug**: Capturing SOPS stdout from encrypting a tempfile and writing it to a different filename lost format metadata needed for SOPS to later edit files with `.enc` extensions.

**Test gap**: Unit tests verified mechanics (correct args, file written) but not validity (can SOPS use the output?). Integration tests that would run actual SOPS commands were skipped unless `RUN_INTEGRATION=1` was set.

### Mitigation

**Code fix**: Use in-place encryption (`sops -e -i --age <key> target.enc`) instead of stdout capture. Write plain content to target file first, then let SOPS encrypt it in-place with proper format detection.

**Aligns with existing pattern**: The working `Init.create_initial_credentials` already used this approach.

### Prevention

- **Round-trip testing**: Tests that write should also verify reading/editing
- **Run integration tests in CI**: Even if slower, they catch format/protocol issues unit tests can't
- **Validate against real tools**: When wrapping external commands, test with the actual binary, not just mocks
- **Beware of fake data**: Mock return values like `"sops_encrypted_content_here"` hide format/encoding issues

### Code Changes

Changed from stdout capture:
```ruby
stdout, stderr, status = Open3.capture3(env, "sops", "-e", temp.path)
File.write(file_path_str, stdout)  # Lost SOPS metadata
```

To in-place encryption:
```ruby
File.write(file_path_str, content)
Open3.capture3(env, "sops", "-e", "-i", "--age", public_key, file_path_str)
```

---

## Incident: Private Key Resolution Divergence Between Debug and Configuration

**Date**: 2024

**Type**: False Positive / Critical Test Missing

### Problem Summary

The private key resolution logic was implemented in two separate places:

1. `SopsRails::Debug#detect_key_source` - Used for debug logging and reporting
2. `SopsRails::Configuration#resolved_age_key_file` - Used for actual decryption operations

These two implementations could diverge, causing `Debug.log_key_info` to report that a different key was being used than the one actually used by `Configuration.resolved_age_key_file` for decryption. This created a situation where:

- Debug output showed one key source/file
- Actual decryption used a different key source/file
- Decryption failed because the wrong key was being used/reported
- Tests could pass if they only tested one code path, but the code would fail in production

### Root Cause

The key resolution logic was duplicated between `Debug` and `Configuration` modules. When the logic needed to be updated (e.g., priority order, edge cases, file existence checks), both places had to be updated separately, making it easy for them to diverge.

### Mitigation

Refactored the code to deduplicate key resolution logic and expose the actual resolved key:

1. **Centralized logic in Configuration**: `Configuration#resolved_age_key_file` is the single source of truth for key resolution used by actual decryption operations
2. **Debug exposes actual resolved key**: `Debug` now calls `config.resolved_age_key_file` and `config.public_key` to show what key is actually being used, alongside the detected source
3. **Divergence visibility**: Debug output now shows both the detected key source (from `detect_key_source`) and the actual resolved key file (from `config.resolved_age_key_file`), making any divergence immediately visible

### Code Changes

The `Debug` module now uses `Configuration` methods to show the actual resolved key:
- `Debug.log_resolved_key_info` calls `config.resolved_age_key_file` to log the actual key file used for decryption
- `Debug.info` includes `resolved_key_file` from `config.resolved_age_key_file` and `public_key` from `config.public_key`
- `Debug.log_key_info` logs both the detected source (from `detect_key_source`) and the actual resolved key file (from `config.resolved_age_key_file`), making any divergence visible

This ensures that even if `detect_key_source` logic diverges from `resolved_age_key_file`, the debug output shows both what was detected and what is actually being used, allowing users to identify mismatches.

### Prevention

- **Single source of truth**: Core business logic (like key resolution) should exist in one place
- **Composition over duplication**: Debug/logging modules should use the same logic as production code, not reimplement it
- **Integration tests**: Test that debug output matches actual behavior, not just that debug methods work in isolation

---

## Incident: Empty Environment Variables and Platform-Specific Key Paths

**Date**: 2024-12-27

**Type**: Production Bug / Test Environment Pollution

### Problem Summary

After clean `sops:init`, decryption immediately failed with "no master key was able to decrypt the file". The issue manifested when `SOPS_AGE_KEY_FILE` was set to empty string (`export SOPS_AGE_KEY_FILE=""`):

1. Empty env var treated as truthy: `ENV.fetch("SOPS_AGE_KEY_FILE", nil)` returned `""`, which is truthy in Ruby
2. `File.expand_path("")` returned current working directory instead of error
3. Directory passed `File.exist?` and `File.readable?` checks
4. Debug showed: `Key file: /Users/tomas/git/projects/ai-jam (exists: true, readable: true)`

**Platform divergence**: Debug checked `~/.config/sops/age/keys.txt` but SOPS on macOS uses `~/Library/Application Support/sops/age/keys.txt` by default.

**Architectural issue**: We detected keys but never passed them to SOPS subprocess, so SOPS used its own (different) detection logic.

### Root Cause

1. **Empty string handling**: Configuration didn't normalize empty env vars to `nil`
2. **Platform paths**: Hardcoded Linux XDG path instead of OS-aware defaults
3. **Key passing**: Binary called SOPS without passing detected key via `SOPS_AGE_KEY_FILE` env
4. **Test pollution**: User's environment variables leaked into tests, causing hard-to-reproduce failures

### Mitigation

**Configuration fixes**:
- Added `presence()` helper to normalize empty strings to `nil`
- Added OS-aware constants: `DEFAULT_AGE_KEY_PATH_MACOS` and `DEFAULT_AGE_KEY_PATH_XDG`
- Added `default_age_key_path` method using `RUBY_PLATFORM.include?("darwin")`
- Added `public_key` extractor to show which key is being used

**Binary fixes**:
- Added `build_sops_env` to build environment hash with resolved key
- Modified `decrypt` to pass env hash to `Open3.capture3(env, "sops", ...)`
- Ensures SOPS uses the same key we detected

**Debug enhancements**:
- Now shows both detected source AND resolved key file used
- Displays public key for easy verification
- Makes divergence visible immediately

**Test isolation**:
- Wrapped all specs in `around` blocks that save/clear/restore env vars
- Prevents user's environment from affecting test results
- Mocks default key path to not exist for predictable behavior

### Prevention

- **Normalize inputs early**: Treat empty strings as `nil` at configuration boundaries
- **Platform awareness**: Use `RUBY_PLATFORM` checks for OS-specific defaults
- **Explicit is better**: Pass detected values explicitly to subprocesses, don't rely on parallel detection
- **Show the money**: Debug output should show actual values being used (like public key), not just paths
- **Test isolation**: Always clean environment variables in test setup, never assume clean state
- **Shared contexts**: Use RSpec shared contexts for common test setup (env isolation, mocking)

### Code Pattern

Environment variable normalization:
```ruby
def presence(value)
  return nil if value.nil? || value.empty?
  value
end

@age_key_file = presence(ENV.fetch("SOPS_AGE_KEY_FILE", nil))
```

OS-aware defaults:
```ruby
def default_age_key_path
  path = macos? ? DEFAULT_AGE_KEY_PATH_MACOS : DEFAULT_AGE_KEY_PATH_XDG
  File.expand_path(path)
end

def macos?
  RUBY_PLATFORM.include?("darwin")
end
```

Test isolation:
```ruby
around do |example|
  original = ENV.fetch("SOPS_AGE_KEY_FILE", nil)
  ENV.delete("SOPS_AGE_KEY_FILE")
  SopsRails.reset!
  example.run
ensure
  ENV["SOPS_AGE_KEY_FILE"] = original if original
  ENV.delete("SOPS_AGE_KEY_FILE") unless original
  SopsRails.reset!
end
```

---
