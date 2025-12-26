# Architectural Decision Records (ADR)

This document captures significant architectural decisions made during the development of sops_rails. Each decision includes context, the choice made, and reasoning.

---

## ADR-001: Use SOPS Binary via Shell Execution

**Status:** Accepted
**Date:** 2025-12-26
**Stage:** 1.2 (SOPS Binary Interface)

### Context

We need to decrypt SOPS-encrypted files. Options considered:

1. **Shell out to SOPS binary** — Execute `sops -d <file>` and capture stdout
2. **Native Ruby implementation** — Parse SOPS format and decrypt using Ruby crypto libraries
3. **SOPS Go library via FFI** — Link to SOPS as a shared library

### Decision

Use shell execution to the SOPS binary via Ruby's `Open3.capture3`.

### Rationale

- **Reliability**: SOPS binary is the reference implementation; avoids reimplementing complex encryption logic
- **Compatibility**: Automatically supports all SOPS features (age, GPG, AWS KMS, etc.) and future updates
- **Simplicity**: Much less code to maintain than a native implementation
- **Security**: SOPS handles all crypto operations; we don't need to manage keys directly
- **Trade-off**: Requires SOPS binary in PATH; acceptable since developers/CI already need it for editing

### Consequences

- SOPS must be installed on developer machines and CI
- Need clear error messages when binary is missing
- Version compatibility checking recommended

---

## ADR-002: Memory-Only Decryption

**Status:** Accepted
**Date:** 2025-12-26
**Stage:** 1.2 (SOPS Binary Interface)

### Context

Decrypted secrets must be accessible to the Rails application but should minimize exposure risk.

### Decision

Never write decrypted content to the filesystem. Capture SOPS stdout directly into Ruby strings.

### Rationale

- **Security**: Temp files can be recovered; memory is cleared on process exit
- **Simplicity**: No cleanup of temp files needed
- **Rails Convention**: Similar to how Rails credentials work (decrypt to memory)

### Consequences

- Cannot use file-based workflows for decrypted content
- Large secrets files held in memory (acceptable for typical credential sizes)

---

## ADR-003: age as Primary Key Format

**Status:** Accepted
**Date:** 2025-12-26
**Stage:** 1.1 (Configuration Module)

### Context

SOPS supports multiple encryption backends: age, GPG, AWS KMS, GCP KMS, Azure Key Vault, HashiCorp Vault.

### Decision

Design primarily around age keys, with other backends as optional/advanced use cases.

### Rationale

- **Simplicity**: age has simpler key management than GPG
- **Modern**: age is the recommended successor to GPG for file encryption
- **Portability**: age keys are simple strings, easy to share and backup
- **SOPS Default**: SOPS recommends age for new projects

### Consequences

- Init wizard generates age keys by default
- Documentation focuses on age workflow
- Other backends work but aren't explicitly supported in rake tasks

---

## ADR-004: OpenStruct-like Credentials Access

**Status:** Accepted
**Date:** 2025-12-26
**Stage:** 1.3 (Credentials Reader)

### Context

Need to provide convenient access to nested credential values.

### Decision

Implement a custom class that allows method chaining (`credentials.aws.access_key_id`) and returns `nil` for missing keys.

### Rationale

- **Familiarity**: Matches Rails credentials API (`Rails.application.credentials.aws.access_key_id`)
- **Safety**: Returning `nil` for missing keys prevents NoMethodError on typos
- **Flexibility**: Can add methods like `fetch`, `dig`, `to_h` as needed

### Consequences

- Custom class implementation instead of raw Hash
- Need to handle method_missing carefully for predictable behavior
- Type signatures (RBS) more complex than for plain Hash

---

## ADR-005: Lazy Loading of Credentials

**Status:** Accepted
**Date:** 2025-12-26
**Stage:** 1.3 (Credentials Reader)

### Context

When should credentials be loaded from encrypted files?

### Decision

Load credentials lazily on first access to `Sops.credentials`.

### Rationale

- **Fast Boot**: Don't slow down Rails boot if credentials aren't used immediately
- **Error Isolation**: Decryption errors occur at usage site, not during require
- **Optional Usage**: Gem can be loaded without credentials file present

### Consequences

- First access may be slow (SOPS execution)
- Errors surface at runtime, not boot time
- Need `Sops.reload!` method to refresh cached credentials

---

## ADR-006: Production Mode with Pre-Decrypted Files

**Status:** Accepted
**Date:** 2025-12-26
**Stage:** 4.1 (Production Mode)

### Context

Production containers often don't have SOPS binary or private keys. Kubernetes/Docker patterns mount decrypted secrets from external secret managers.

### Decision

Support a "decrypted mode" where the gem reads plain YAML files instead of calling SOPS.

### Rationale

- **Separation of Concerns**: Decryption handled by infrastructure (FluxCD, ArgoCD, Vault Agent)
- **Security**: Private keys never in production containers
- **Simplicity**: No SOPS binary needed in production images
- **Compatibility**: Works with any secret injection mechanism

### Consequences

- Two code paths: encrypted mode (dev) and decrypted mode (prod)
- Need clear documentation on deployment patterns
- `DECRYPTED_SECRETS_PATH` environment variable convention

---

## ADR-007: Minimal Railtie for Rails Integration

**Status:** Accepted
**Date:** 2025-12-26
**Stage:** 1.4 (Rails Integration)

### Context

The gem needs to integrate with Rails applications so that `SopsRails.credentials` is available throughout the app—in initializers, models, controllers, views, and ERB config files like `database.yml`.

Options considered:

1. **Minimal Railtie** — Just inherit from `Rails::Railtie`, rely on Bundler auto-loading
2. **Railtie with initializer hooks** — Use `initializer` blocks to set up configuration
3. **Engine** — Full Rails Engine with routes, assets, etc.

### Decision

Use a minimal Railtie that simply inherits from `Rails::Railtie` without custom initializer hooks.

### Rationale

- **Simplicity**: Bundler automatically loads the gem when Rails boots, making `SopsRails` available immediately
- **Early Availability**: The gem is loaded before `database.yml` is processed, enabling ERB like `<%= SopsRails.credentials.db.password %>`
- **Convention**: Rails initializers (`config/initializers/sops.rb`) are loaded automatically—no need for explicit Railtie hooks
- **Lazy Loading**: Credentials are loaded on first access (ADR-005), so no Railtie setup is required
- **Less Code**: No custom hooks means less code to maintain and fewer edge cases

### Consequences

- Configuration happens via `config/initializers/sops.rb` (standard Rails pattern)
- No automatic Rails.env-based configuration (can be added in Stage 4)
- Works seamlessly with ERB in YAML config files
- Testing requires mocking Rails, but the minimal implementation keeps tests simple

---

## Template for New Decisions

```markdown
## ADR-XXX: [Title]

**Status:** Proposed | Accepted | Deprecated | Superseded
**Date:** YYYY-MM-DD
**Stage:** X.Y (Feature Name)

### Context

What is the issue we're addressing?

### Decision

What is the change we're proposing/making?

### Rationale

Why is this the best choice among alternatives?

### Consequences

What are the results of this decision?
```
