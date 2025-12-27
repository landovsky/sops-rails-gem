# Architecture Review & Recommendations

**Review Date:** 2024-12-27
**Reviewed Version:** Stage 2 (Developer Workflow)

This document provides an architectural review of the sops_rails gem, evaluating code quality, design patterns, and alignment with best practices. Recommendations are split into three priorities based on impact and urgency.

---

## Executive Summary

The sops_rails gem demonstrates solid architectural foundations with good separation of concerns, thread-safety considerations, and comprehensive documentation. The codebase has learned from past incidents (documented in `03-TEST-INCIDENTS.md`) and incorporates those lessons. However, several areas warrant attention for improved maintainability, consistency, and robustness.

### Strengths Observed

1. **Clear module responsibilities**: `Binary` handles shell execution, `Configuration` manages settings, `Credentials` provides data access, `Debug` offers observability
2. **Thread-safety**: Proper mutex usage with separate mutexes to avoid deadlock (learned from incidents)
3. **Security-first design**: Memory-only decryption, never writes secrets to filesystem
4. **Platform awareness**: OS-specific paths for macOS vs Linux
5. **Comprehensive YARD documentation**: All public methods documented with examples
6. **Test isolation**: Shared contexts for environment cleanup prevent test pollution
7. **Defensive programming**: Input normalization (`presence()` helper), graceful handling of empty env vars

---

## Priority 1: High — Correctness & Security

These issues could lead to bugs, security vulnerabilities, or production incidents. Address before any major release.

### 1.1 Inconsistent SOPS Environment Passing in Init Module

**Location:** `lib/sops_rails/init.rb:272`

**Issue:** `Init.create_initial_credentials` calls SOPS directly without passing the resolved environment variables that `Binary` methods use. This can cause inconsistent behavior where `Binary.encrypt_to_file` works but `Init` fails (or vice versa).

```ruby
# Current (Init.create_initial_credentials)
stdout, stderr, status = Open3.capture3(*sops_args)  # No env hash!

# Binary methods use:
env = build_sops_env
stdout, stderr, status = Open3.capture3(env, *sops_args)
```

**Recommendation:** Refactor `Init` to use `Binary.encrypt_to_file` instead of duplicating SOPS invocation logic, or extract a shared method for building SOPS environment.

**Risk:** Medium — Could cause init to fail when user has custom key configuration.

---

### 1.2 Method Name Mismatch After Bug Fix

**Location:** `lib/sops_rails/binary.rb:169`

**Issue:** The private method `encrypt_via_tempfile` no longer uses a tempfile (fixed per TEST-INCIDENTS). The misleading name could lead future maintainers to reintroduce the bug.

```ruby
# Current name suggests tempfile usage, but implementation does in-place encryption
def encrypt_via_tempfile(file_path_str, content, public_key)
  File.write(file_path_str, content)  # Writes directly to target
  # ...in-place encryption...
end
```

**Recommendation:** Rename to `encrypt_in_place` or `encrypt_file_content` to accurately describe behavior.

---

### 1.3 Duplicate Public Key Extraction Logic

**Location:** `lib/sops_rails/configuration.rb:168-174` and `lib/sops_rails/init.rb:159-166`

**Issue:** Public key extraction from age key files is implemented twice with slightly different regex patterns:

```ruby
# Configuration
match = line.match(/^#\s*public key:\s*(age1\S+)/)

# Init
match = content.match(/^# public key: (age1[a-z0-9]+)/)
```

The patterns differ in whitespace handling (`\s*` vs literal space) and character class (`\S+` vs `[a-z0-9]+`). This could cause one to succeed where the other fails.

**Recommendation:** Extract to a single shared method in `Configuration` and have `Init` delegate to it, similar to how `Init.age_keys_path` already delegates.

---

### 1.4 Missing Error Context in Init Module

**Location:** `lib/sops_rails/init.rb`

**Issue:** When `Init.run` fails partway through (e.g., key generation succeeds but `.sops.yaml` creation fails), users have no way to know what was created vs. what failed. Partial state is left behind.

**Recommendation:**

- Add transaction-like cleanup on failure (remove partially created files)
- Or explicitly document which steps succeeded before the error
- Consider adding `--dry-run` flag for preview

---

## Priority 2: Medium — Maintainability & Consistency

These issues increase technical debt and make the codebase harder to maintain. Address in normal development cycles.

### 2.1 Code Duplication in Rake Task Modules

**Location:** `lib/sops_rails/tasks/sops.rake:9-100`

**Issue:** `SopsShowTask` and `SopsEditTask` are nearly identical (already noted in TD-1). They share:

- `resolve_file_path` method (identical)
- `env_credentials_path` method (identical)
- `default_credentials_path` method (identical)

**Recommendation:** Extract shared logic to `SopsTaskHelper` base module:

```ruby
module SopsTaskHelper
  def resolve_file_path(file_arg)
    return file_arg if file_arg && !file_arg.empty?
    return env_credentials_path(ENV["RAILS_ENV"]) if ENV["RAILS_ENV"]
    default_credentials_path
  end

  private

  def env_credentials_path(environment)
    File.join(SopsRails.config.encrypted_path, "credentials.#{environment}.yaml.enc")
  end

  def default_credentials_path
    config = SopsRails.config
    File.join(config.encrypted_path, config.credential_files.first)
  end
end
```

---

### 2.2 NullCredentials in Credentials File

**Location:** `lib/sops_rails/credentials.rb:271-338`

**Issue:** `NullCredentials` is a significant public API component (Null Object pattern) but lives inside the `Credentials` file. This makes it:

- Harder to find when debugging
- Harder to test independently
- Violates single-responsibility at file level

**Recommendation:** Extract to `lib/sops_rails/null_credentials.rb` with its own dedicated spec file.

---

### 2.3 Require Statement Inside Method

**Location:** `lib/sops_rails/binary.rb:153`

**Issue:** `require "tempfile"` is called inside `encrypt_to_file` method. While this is a minor lazy-loading pattern, it's inconsistent with the rest of the codebase where requires are at the top.

```ruby
def encrypt_to_file(file_path, content, public_key: nil)
  # ...
  require "tempfile"  # Should be at top of file
  encrypt_via_tempfile(file_path_str, content, public_key)
end
```

**Recommendation:** Move to top-level requires. Note: The tempfile require may be vestigial from the old implementation.

---

### 2.4 Debug Module Size

**Location:** `lib/sops_rails/debug.rb`

**Issue:** The `Debug` module has grown to ~240 lines with many private methods. While well-documented, the complexity suggests it might benefit from decomposition.

**Recommendation:** Consider extracting:

- `KeySourceDetector` — handles key detection logic
- `InfoBuilder` — constructs debug info hashes

This would also help prevent the "divergence between Debug and Configuration" incident from recurring.

---

### 2.5 Inconsistent Guard Clause Style

**Location:** Various files

**Issue:** Some guards use multi-line blocks, others use single-line:

```ruby
# Single-line (preferred per .cursor/rules)
raise SopsNotFoundError, "message" unless status.success?

# Multi-line (used in some places)
unless status.success?
  raise EncryptionError, "message"
end
```

**Recommendation:** Standardize on single-line guard clauses per project rules. Run RuboCop with `Style/GuardClause` enabled.

---

## Priority 3: Low — Polish & Future-Proofing

Nice-to-have improvements that would enhance code quality but aren't blocking.

### 3.1 Missing Integration Test Fixtures

**Location:** `spec/sops_rails/binary_spec.rb:557`

**Issue:** Integration tests reference `spec/fixtures/test_credentials.yaml.enc` but the fixture doesn't exist. Tests skip gracefully but this means integration coverage is incomplete.

**Recommendation:**

- Add CI job that runs integration tests with SOPS binary
- Create fixture files as part of test setup (using `sops:init`-like logic)
- Document how to run integration tests locally in CONTRIBUTING.md

---

### 3.2 Configuration Could Use Value Objects

**Location:** `lib/sops_rails/configuration.rb`

**Issue:** Configuration returns raw strings and arrays. For better encapsulation, consider value objects:

```ruby
# Current
config.resolved_age_key_file  # => "/path/to/keys.txt" or nil

# Potential improvement
config.age_key.path          # => "/path/to/keys.txt"
config.age_key.exists?       # => true
config.age_key.public_key    # => "age1..."
config.age_key.source        # => :env_file, :env_var, :default, :none
```

**Recommendation:** Consider for Stage 4+ when adding more key management features.

---

### 3.3 Consider Dry-Types for Configuration Validation

**Issue:** Configuration validation is manual and scattered. A schema library could provide:

- Type checking at configuration time
- Clear documentation of valid values
- Better error messages for invalid config

**Recommendation:** Evaluate dry-types or ActiveModel::Validations for configuration object. Low priority as current validation is adequate.

---

### 3.4 Railtie Could Load Earlier

**Location:** `lib/sops_rails/railtie.rb`

**Issue:** The Railtie is minimal (by design per ADR-007), but it only loads rake tasks. For Stage 4 features (production mode, caching), consider adding:

```ruby
initializer "sops_rails.configure" do |app|
  # Set defaults based on Rails.env
  # Configure caching
end
```

**Recommendation:** Revisit when implementing Stage 4 Production Deployment features.

---

### 3.5 Error Messages Could Include Resolution Steps

**Issue:** Error messages describe what went wrong but don't always suggest fixes:

```ruby
# Current
raise DecryptionError, "failed to decrypt file #{file_path}: #{error_message}"

# Better
raise DecryptionError, <<~MSG
  Failed to decrypt #{file_path}: #{error_message}

  Troubleshooting:
  - Verify your age key is available: run `sops:debug`
  - Check file exists and is a valid SOPS file
  - Ensure your key is listed in .sops.yaml
MSG
```

**Recommendation:** Implement as part of Stage 5.4 (Enhanced Error Messages).

---

## Test Architecture Notes

Based on review of `03-TEST-INCIDENTS.md` and current test structure:

### What's Working Well

1. **Environment isolation** via `with clean environment` shared context
2. **Shared examples** for common patterns (`requires sops binary`)
3. **Integration test skip logic** when SOPS unavailable
4. **Separate concerns** — unit tests mock Open3, integration tests use real binary

### Areas to Watch

1. **Round-trip tests**: The encrypt_to_file incident showed unit tests passing with fake data. Ensure integration tests verify full workflows.

2. **Configuration tests**: Tests reset config but may not fully test all state transitions. Consider property-based testing for configuration edge cases.

3. **Debug/Configuration divergence**: Add integration test that verifies `Debug.info[:resolved_key_file]` matches what `Binary` actually uses.

---

## Recommended Action Plan

### Immediate (Before Stage 3)

- [ ] Fix Init.create_initial_credentials to use Binary.encrypt_to_file or shared env building
- [ ] Rename `encrypt_via_tempfile` to `encrypt_in_place`
- [ ] Unify public key extraction regex patterns

### Short-term (Stage 3)

- [ ] Extract shared rake task helper module
- [ ] Move NullCredentials to own file
- [ ] Add integration test fixtures
- [ ] Move `require "tempfile"` to top of file (or remove if unused)

### Medium-term (Stage 4+)

- [ ] Consider key source value objects
- [ ] Enhance error messages with troubleshooting steps
- [ ] Add dry-run support to Init

---

## References

- `00-DEVELOPMENT-ROAD-MAP.md` — Feature roadmap
- `01-ARCHITECTURAL-DECISIONS.md` — Design rationale
- `03-TEST-INCIDENTS.md` — Past bugs and lessons learned
