# Test Architecture Recommendations

## Problem Summary

The `Binary.encrypt_to_file` unit tests verified command execution mechanics but not output validity. Tests passed while actual functionality was broken because:

1. **Mocked return values were fake strings** - not real SOPS output
2. **No round-trip verification** - never verified encrypted output could be decrypted
3. **Integration tests skipped** - tests that would catch issues were gated behind `RUN_INTEGRATION=1`

## Root Cause

The old implementation captured SOPS stdout and wrote it to a file. The output was syntactically valid but missing SOPS format metadata needed for subsequent `sops edit` operations. Unit tests couldn't detect this because they mocked SOPS entirely.

## Recommendations

### 1. Add Round-Trip Integration Tests for Encryption

**Priority: HIGH**

Add integration tests that verify encryption produces files that SOPS can actually work with:

```ruby
# spec/sops_rails/binary_spec.rb

describe ".encrypt_to_file", integration: true do
  let(:temp_dir) { Dir.mktmpdir }
  let(:test_file) { File.join(temp_dir, "test_credentials.yaml.enc") }
  let(:plain_content) { "aws:\n  access_key_id: test123\n" }
  let(:sops_config) { File.join(Dir.pwd, ".sops.yaml") }

  before do
    skip "SOPS binary not available" unless described_class.available?
    skip "Integration tests require .sops.yaml" unless File.exist?(sops_config)
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  it "creates an encrypted file that can be decrypted" do
    # Encrypt
    result = described_class.encrypt_to_file(test_file, plain_content)
    expect(result).to be true
    expect(File.exist?(test_file)).to be true

    # Verify it's actually encrypted (not plain text)
    file_content = File.read(test_file)
    expect(file_content).not_to include("test123")
    expect(file_content).to include("sops:") # SOPS metadata

    # Decrypt and verify content matches
    decrypted = described_class.decrypt(test_file)
    expect(decrypted).to eq(plain_content)
  end

  it "creates a file that can be edited with sops edit" do
    described_class.encrypt_to_file(test_file, plain_content)

    # Verify file status is valid
    stdout, stderr, status = Open3.capture3("sops", "--file-status", test_file)
    expect(status.success?).to be true, "File status check failed: #{stderr}"

    # Verify file can be decrypted (indirectly tests edit capability)
    # If sops edit works, decrypt should work
    expect { described_class.decrypt(test_file) }.not_to raise_error
  end

  it "preserves SOPS metadata required for editing" do
    described_class.encrypt_to_file(test_file, plain_content)

    # Check that file has proper SOPS structure
    file_content = File.read(test_file)
    parsed = YAML.safe_load(file_content)

    # SOPS files should have sops metadata
    expect(parsed).to have_key("sops")
    expect(parsed["sops"]).to have_key("mac")
    expect(parsed["sops"]).to have_key("lastmodified")
  end
end
```

### 2. Make Integration Tests Run by Default (with Smart Skipping)

**Priority: HIGH**

Integration tests should run by default but skip gracefully when prerequisites are missing:

```ruby
# spec/spec_helper.rb

RSpec.configure do |config|
  # ... existing config ...

  # Run integration tests by default, but skip if prerequisites missing
  config.filter_run_excluding integration: true unless ENV["SKIP_INTEGRATION"] == "1"
end
```

**Benefits:**
- Catches regressions immediately in CI
- Developers see failures locally if they break encryption
- Still skips gracefully when SOPS/age not available

**Alternative:** Use RSpec metadata to mark tests that require real binaries:

```ruby
# In spec_helper.rb
RSpec.configure do |config|
  config.before(:example, :integration) do |example|
    unless SopsRails::Binary.available?
      skip "SOPS binary not available (install SOPS to run integration tests)"
    end
  end
end
```

### 3. Add Contract Tests for SOPS Output Format

**Priority: MEDIUM**

Create a shared example that verifies encrypted files meet SOPS format requirements:

```ruby
# spec/support/shared_examples/sops_file_contract.rb

RSpec.shared_examples "a valid SOPS encrypted file" do |file_path|
  it "contains SOPS metadata" do
    content = File.read(file_path)
    parsed = YAML.safe_load(content)

    expect(parsed).to have_key("sops")
    expect(parsed["sops"]).to be_a(Hash)
  end

  it "can be decrypted by SOPS" do
    stdout, stderr, status = Open3.capture3("sops", "-d", file_path)
    expect(status.success?).to be true, "Decryption failed: #{stderr}"
    expect(stdout).not_to be_empty
  end

  it "passes sops --file-status check" do
    stdout, stderr, status = Open3.capture3("sops", "--file-status", file_path)
    expect(status.success?).to be true, "File status check failed: #{stderr}"
  end
end

# Usage in tests:
it_behaves_like "a valid SOPS encrypted file", test_file
```

### 4. Improve Unit Test Assertions

**Priority: MEDIUM**

Even in unit tests, verify that the implementation calls SOPS correctly:

```ruby
# Better unit test that verifies command structure
it "calls sops with in-place encryption flags" do
  expect(Open3).to receive(:capture3) do |env, *args|
    # Verify command structure
    expect(args).to eq(["sops", "-e", "-i", file_path])
    # Verify environment includes key info if available
    if SopsRails.config.age_key
      expect(env).to have_key("SOPS_AGE_KEY")
    end
    ["", "", success_status]
  end

  described_class.encrypt_to_file(file_path, content)
end
```

### 5. Add Test Fixtures for Integration Tests

**Priority: LOW**

Create encrypted test fixtures that can be used for integration tests:

```ruby
# spec/fixtures/credentials.yaml.enc
# This should be a real SOPS-encrypted file committed to the repo
# Encrypted with a test key that's documented in the test setup

# In tests:
let(:fixture_file) { "spec/fixtures/credentials.yaml.enc" }

it "can decrypt fixture files" do
  content = described_class.decrypt(fixture_file)
  expect(content).to include("test_key")
end
```

**Note:** Use a test-only age key for fixtures, documented in `spec/README.md`.

### 6. Add Validation Helper Methods

**Priority: LOW**

Create helper methods that can be used in both unit and integration tests:

```ruby
# spec/support/helpers/sops_validation_helper.rb

module SopsValidationHelper
  def valid_sops_file?(file_path)
    return false unless File.exist?(file_path)

    content = File.read(file_path)
    parsed = YAML.safe_load(content)
    parsed.is_a?(Hash) && parsed.key?("sops")
  rescue Psych::SyntaxError
    false
  end

  def can_decrypt_with_sops?(file_path)
    return false unless SopsRails::Binary.available?

    stdout, stderr, status = Open3.capture3("sops", "-d", file_path)
    status.success?
  end
end

RSpec.configure do |config|
  config.include SopsValidationHelper
end
```

## Implementation Priority

1. **Immediate (This Sprint):**
   - Add round-trip integration test for `encrypt_to_file`
   - Make integration tests run by default (with smart skipping)

2. **Short Term (Next Sprint):**
   - Add contract tests for SOPS file format
   - Improve unit test assertions

3. **Long Term (When Time Permits):**
   - Add test fixtures
   - Add validation helpers

## Testing Strategy Summary

| Test Type | Purpose | When to Run | Example |
|-----------|---------|-------------|---------|
| **Unit Tests** | Verify method calls, error handling, command construction | Always | Mock Open3, verify args |
| **Integration Tests** | Verify actual SOPS operations work end-to-end | Always (skip if no SOPS) | Real encrypt → decrypt round-trip |
| **Contract Tests** | Verify output format matches SOPS spec | Always (skip if no SOPS) | Check YAML structure, metadata |
| **Fixtures** | Test with known-good encrypted files | Always | Decrypt committed test files |

## Anti-Patterns to Avoid

❌ **Don't:** Mock SOPS output with fake strings in encryption tests
```ruby
# BAD
let(:encrypted_content) { "sops_encrypted_content_here" }
allow(Open3).to receive(:capture3).and_return([encrypted_content, "", success])
```

✅ **Do:** Use real SOPS in integration tests, or verify command structure in unit tests
```ruby
# GOOD - Integration
it "creates decryptable file" do
  described_class.encrypt_to_file(file, content)
  expect(described_class.decrypt(file)).to eq(content)
end

# GOOD - Unit
it "calls sops with correct args" do
  expect(Open3).to receive(:capture3) do |env, *args|
    expect(args).to eq(["sops", "-e", "-i", file_path])
    ["", "", success]
  end
end
```

❌ **Don't:** Gate integration tests behind environment variables
```ruby
# BAD
skip "Integration tests skipped" unless ENV["RUN_INTEGRATION"] == "1"
```

✅ **Do:** Skip gracefully when prerequisites missing
```ruby
# GOOD
skip "SOPS binary not available" unless SopsRails::Binary.available?
```

## CI/CD Considerations

- **CI should always run integration tests** (SOPS/age should be installed in CI)
- Use `SKIP_INTEGRATION=1` only for local development when binaries unavailable
- Fail CI builds if integration tests fail (don't allow skipping in CI)

## Related Files

- `spec/sops_rails/binary_spec.rb` - Main test file to update
- `spec/spec_helper.rb` - RSpec configuration
- `lib/sops_rails/binary.rb` - Implementation being tested

## References

- [SOPS File Format Documentation](https://github.com/mozilla/sops/blob/master/docs/file-format.md)
- [RSpec Integration Test Best Practices](https://rspec.info/documentation/3.12/rspec-core/RSpec/Core/Configuration.html#filter_run_excluding-instance_method)
