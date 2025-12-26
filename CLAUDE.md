# CLAUDE.md - AI Assistant Guidelines for sops_rails

## Project Overview

**sops_rails** is a Ruby gem that integrates Mozilla SOPS (Secrets OPerationS) encryption with Rails applications. It enables teams to manage encrypted credentials with visible YAML structure and individual age keys per developer.

## Development Philosophy

### Trustworthy & Verifiable Code

1. **Test-Driven Development** — Write tests before or alongside implementation. Every feature must have corresponding specs.
2. **Small, Focused Commits** — Each commit should address one logical change.
3. **Documentation as Code** — All public APIs must have YARD documentation with examples.
4. **Explicit over Implicit** — Prefer clear, readable code over clever shortcuts.

### Code Style Requirements

- **Ruby Style**: Follow standard Ruby conventions (RuboCop defaults)
- **Class/Module Documentation**: Every class and module MUST have a descriptive comment block explaining its purpose
- **Method Comments**: Non-trivial methods should have inline comments explaining the "why"
- **Frozen String Literals**: All files start with `# frozen_string_literal: true`

### Example of Well-Documented Code

```ruby
# frozen_string_literal: true

module SopsRails
  # Handles interaction with the SOPS binary for encryption/decryption operations.
  #
  # This class wraps the SOPS CLI to provide a clean Ruby interface. All decryption
  # happens in-memory to prevent secrets from touching the filesystem.
  #
  # @example Check if SOPS is available
  #   SopsRails::Binary.available? #=> true
  #
  # @example Decrypt a file
  #   content = SopsRails::Binary.decrypt("config/credentials.yaml.enc")
  #
  class Binary
    # Minimum supported SOPS version
    MINIMUM_VERSION = "3.7.0"

    # Decrypts a SOPS-encrypted file and returns the plaintext content.
    #
    # @param file_path [String] Path to the encrypted file
    # @return [String] Decrypted content
    # @raise [SopsNotFoundError] if SOPS binary is not installed
    # @raise [DecryptionError] if decryption fails
    def self.decrypt(file_path)
      # Implementation here...
    end
  end
end
```

## Implementation Guidelines

### When Adding New Features

1. **Check the Roadmap** — Reference `docs/implementation/00-DEVELOPMENT-ROAD-MAP.md` for feature specs
2. **Document Decisions** — Major architectural choices go in `docs/implementation/01-ARCHITECTURAL-DECISIONS.md`
3. **Follow Stage Order** — Build upon completed stages; don't skip ahead

### File Organization

```
lib/
├── sops_rails.rb           # Main entry point, requires all components
├── sops_rails/
│   ├── version.rb          # Gem version constant
│   ├── configuration.rb    # Configuration singleton (Stage 1.1)
│   ├── binary.rb           # SOPS CLI wrapper (Stage 1.2)
│   ├── credentials.rb      # Credentials reader (Stage 1.3)
│   ├── railtie.rb          # Rails integration (Stage 1.4)
│   ├── errors.rb           # Custom exception classes
│   └── tasks/              # Rake tasks (Stage 2+)
│       ├── show.rake
│       ├── edit.rake
│       └── init.rake
```

### Error Handling

- Define specific exception classes in `lib/sops_rails/errors.rb`
- Include actionable error messages that help users fix the problem
- Never expose sensitive data in error messages

### Testing Strategy

- **Unit Tests**: Test individual classes in isolation with mocks
- **Integration Tests**: Test with real SOPS/age binaries (mark with `integration: true`)
- **Use fixtures**: Store test encrypted files in `spec/fixtures/`

## Verification Checklist

Before considering any feature complete:

- [ ] All acceptance criteria from roadmap pass
- [ ] RSpec tests written and passing (`bundle exec rspec`)
- [ ] RuboCop passes (`bundle exec rubocop`)
- [ ] YARD documentation complete (`yard doc` shows no warnings)
- [ ] Manual testing in a real Rails app (when applicable)

## Commands Reference

```bash
# Run tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/sops_rails/binary_spec.rb

# Check code style
bundle exec rubocop

# Auto-fix style issues
bundle exec rubocop -a

# Generate documentation
yard doc

# Run console with gem loaded
bin/console
```

## Security Considerations

- **Never log secrets** — Even in debug mode
- **Memory-only decryption** — Decrypted content must never touch the filesystem
- **Sanitize user input** — Especially in rake tasks that accept arguments
- **Validate key formats** — Verify age public keys match expected format before use
