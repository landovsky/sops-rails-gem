# SOPS-Rails Implementation Plan v2

A detailed agile roadmap for implementing the sops-rails gem. Each stage delivers incremental, testable value while building toward the complete feature set.

---

## [DONE] Stage 1: Core MVP — Read Encrypted Credentials ✅

**Goal:** Enable Rails applications to read SOPS-encrypted YAML credential files in development mode.

**Value Delivered:** Developers can store secrets in SOPS-encrypted files and access them programmatically in their Rails application. This provides the foundational value proposition—secrets with visible structure and team-friendly encryption.

### Features

#### [DONE] 1.1 Configuration Module

Create the base configuration system that stores gem settings.

**Description:**
- Implement `Sops.configure` block-style configuration
- Support `encrypted_path` option (default: `'config'`)
- Support `credential_files` option (default: `['credentials.yaml.enc']`)
- Read `SOPS_AGE_KEY_FILE` and `SOPS_AGE_KEY` environment variables
- Store configuration in thread-safe singleton

**Acceptance Criteria:**
- [ ] `Sops.configure { |c| c.encrypted_path = 'custom' }` sets the path
- [ ] `Sops.config.encrypted_path` returns configured value
- [ ] `Sops.config.credential_files` returns array of file patterns
- [ ] Default values are applied when no configuration block provided
- [ ] Configuration is accessible from any Rails context (initializers, models, etc.)

---

#### [DONE] 1.2 SOPS Binary Interface

Create a clean interface for shelling out to the SOPS binary.

**Description:**
- Implement `Sops::Binary` class that wraps SOPS CLI calls
- Detect SOPS binary presence and version
- Execute `sops -d <file>` and capture stdout (decrypted content)
- Handle stderr for error messages
- Never write decrypted content to disk

**Acceptance Criteria:**
- [ ] `Sops::Binary.available?` returns true when sops is installed
- [ ] `Sops::Binary.version` returns version string (e.g., "3.8.1")
- [ ] `Sops::Binary.decrypt(file_path)` returns decrypted content as string
- [ ] Raises `Sops::SopsNotFoundError` when binary not in PATH
- [ ] Raises `Sops::DecryptionError` with meaningful message when decryption fails
- [ ] Decrypted content never touches filesystem (memory-only)

---

#### 1.3 [DONE] Credentials Reader

Parse decrypted YAML and provide convenient access API.

**Description:**
- Implement `Sops::Credentials` class with OpenStruct-like access
- Support method chaining: `credentials.aws.access_key_id`
- Support `dig` method: `credentials.dig(:aws, :access_key_id)`
- Return `nil` for missing keys (no exceptions on missing nested keys)
- Lazy load credentials on first access

**Acceptance Criteria:**
- [ ] `Sops.credentials` returns Credentials object
- [ ] `Sops.credentials.aws.access_key_id` returns string value
- [ ] `Sops.credentials.nonexistent.nested.key` returns `nil` (not error)
- [ ] `Sops.credentials.dig(:aws, :access_key_id)` works correctly
- [ ] Credentials are loaded from file specified in `config.credential_files`
- [ ] Works with valid SOPS-encrypted YAML files

---

#### [DONE] 1.4 Rails Integration (Railtie)

Integrate with Rails boot process.

**Description:**
- Create `SopsRails::Railtie` for Rails integration
- Auto-load configuration from `config/initializers/sops.rb` if present
- Make `SopsRails.credentials` available throughout Rails app
- Support usage in `database.yml` via ERB: `<%= SopsRails.credentials.db.password %>`

**Acceptance Criteria:**
- [x] Gem loads automatically in Rails application
- [x] `SopsRails.credentials` accessible in Rails console
- [x] `SopsRails.credentials` accessible in initializers
- [x] ERB interpolation works in `database.yml`
- [x] No errors when gem loads without credentials file (lazy loading)

---

### Stage 1 Definition of Done

- [x] All acceptance criteria pass
- [x] Unit tests for Configuration, Binary, Credentials, Railtie modules
- [x] Integration test: encrypted file → `SopsRails.credentials` access
- [x] Works with Ruby 3.2+ and Rails 7.0+
- [x] Basic error handling with clear messages

---

## Stage 2: Developer Workflow — Init & Edit 📝

**Goal:** Provide command-line tools for creating and editing encrypted credential files.

**Value Delivered:** Developers have a complete local workflow—they can initialize sops-rails in a project, create encrypted files, and edit them securely without manually running SOPS commands.

### Features

#### [DONE] 2.1 Rake Task: `sops:show`

Display decrypted credentials in terminal.

**Description:**
- Show decrypted contents of default credentials file
- Support `FILE` argument for specific file
- Support `-e ENVIRONMENT` flag for environment files
- Use same in-memory decryption as credentials reader

**Acceptance Criteria:**
- [ ] `rails sops:show` outputs decrypted YAML to stdout
- [ ] `rails sops:show config/credentials.production.yaml.enc` shows specific file
- [ ] `rails sops:show -e production` shows `credentials.production.yaml.enc`
- [ ] Output is valid YAML format
- [ ] Exits with error code 1 and message if decryption fails

---

#### [DONE] 2.1.1 Add debugging mode

Make it easier to debug issues related to encryption / decryption.

**Description:**
- show which key is being used (key can be in SOPS_AGE_KEY, SOPS_AGE_KEY_FILE or config)

#### [IN PROGRESS] 2.2 Rake Task: `sops:edit`

Edit encrypted credentials in user's editor.

**Description:**
- Open encrypted file in `$EDITOR` (fallback: `vim`, then `nano`)
- Delegate editing to SOPS native edit command (`sops <file>`)
- Create new encrypted file if target doesn't exist
- Support `-e ENVIRONMENT` flag

**Acceptance Criteria:**
- [ ] `rails sops:edit` opens default credentials file in editor
- [ ] `rails sops:edit -e production` opens/creates environment file
- [ ] `rails sops:edit config/custom.yaml.enc` opens specific file
- [ ] Saving in editor re-encrypts the file
- [ ] Aborting editor (exit without save) leaves file unchanged
- [ ] Creating new file prompts for initial content or creates template

---

#### [DONE] 2.3 Rake Task: `sops:init`

Interactive setup wizard for new projects.

**Description:**
- Check for `sops` and `age` binary prerequisites
- Generate age key pair if none exists at standard location
- Create `.sops.yaml` with Rails-friendly creation rules
- Add sops-rails entries to `.gitignore`
- Create initial `config/credentials.yaml.enc` with template
- Support `--non-interactive` flag for CI environments

**Acceptance Criteria:**
- [ ] Exits early with helpful message if `sops` not installed
- [ ] Exits early with helpful message if `age` not installed
- [ ] Creates age key at `~/.config/sops/age/keys.txt` if missing
- [ ] Outputs user's public key for team sharing
- [ ] Creates valid `.sops.yaml` with path regex rules
- [ ] Adds entries to `.gitignore`: `.env*.local`, `*.decrypted.*`, `tmp/secrets/`
- [ ] Creates `config/credentials.yaml.enc` with example structure
- [ ] `--non-interactive` flag skips prompts and uses defaults
- [ ] Doesn't overwrite existing files without confirmation

---

#### 2.4 `.sops.yaml` Template Generator

Generate proper SOPS configuration for Rails projects.

**Description:**
- Create Rails-specific `.sops.yaml` template
- Include path regexes for `config/credentials.*.yaml.enc`
- Include path regexes for `.env.*.enc`
- Add user's age public key as first recipient

**Acceptance Criteria:**
- [ ] Generated `.sops.yaml` is valid YAML
- [ ] Path regex matches `config/credentials.yaml.enc`
- [ ] Path regex matches `config/credentials.production.yaml.enc`
- [ ] Path regex matches `.env.production.enc`
- [ ] SOPS binary can use generated config to encrypt files

---

### Stage 2 Definition of Done

- [ ] All acceptance criteria pass
- [ ] `sops:init` tested on clean project directory
- [ ] `sops:edit` tested with vim and VS Code
- [ ] Works without Rails (for standalone testing)
- [ ] Error messages include actionable solutions

---

## Stage 3: Team Collaboration — Key Management 👥

**Goal:** Enable adding and removing team members' age keys with automatic re-encryption.

**Value Delivered:** Teams can onboard and offboard members without sharing a single master key. Each developer has their own key, and access can be revoked by removing their key and re-encrypting.

### Features

#### 3.1 Rake Task: `sops:keys`

List all authorized age keys.

**Description:**
- Parse `.sops.yaml` and extract all age public keys
- Display keys with associated names/comments
- Show truncated key format for readability
- Indicate which key belongs to current user (if detectable)

**Acceptance Criteria:**
- [ ] Lists all age keys from `.sops.yaml`
- [ ] Shows name/comment if present (e.g., "Alice (alice@example.com)")
- [ ] Truncates long keys for display (first 12 chars + "...")
- [ ] Indicates current user's key with marker (e.g., "(you)")
- [ ] Handles missing `.sops.yaml` with helpful error

---

#### 3.2 Rake Task: `sops:addkey PUBLIC_KEY`

Add a team member's age public key.

**Description:**
- Validate age public key format (`age1...`)
- Add key to `.sops.yaml` recipients list
- Support `--name NAME` option for human-readable identifier
- Re-encrypt all credential files with new key included
- Show progress during re-encryption

**Acceptance Criteria:**
- [ ] `rails sops:addkey age1abc... --name "Alice"` adds key with name
- [ ] Rejects invalid key format with clear error message
- [ ] Updates `.sops.yaml` with new key entry
- [ ] Re-encrypts all matching files (credentials, .env)
- [ ] New key holder can decrypt files after operation
- [ ] Idempotent: adding existing key shows message but doesn't fail
- [ ] Shows list of re-encrypted files

---

#### 3.3 Rake Task: `sops:removekey PUBLIC_KEY`

Remove a team member's access.

**Description:**
- Find key in `.sops.yaml` and show associated name
- Require interactive confirmation (with `--force` override)
- Remove key from `.sops.yaml`
- Re-encrypt all credential files without removed key
- Display warning about secret rotation

**Acceptance Criteria:**
- [ ] Confirms key exists before proceeding
- [ ] Shows key name/identifier before removal
- [ ] Prompts for confirmation: "Remove key age1abc...? [y/N]"
- [ ] `--force` flag skips confirmation
- [ ] Removes key from `.sops.yaml`
- [ ] Re-encrypts all files without removed key
- [ ] Removed key can no longer decrypt files
- [ ] Displays warning: "If this key had access, consider rotating secrets"

---

#### 3.4 Rake Task: `sops:rotate`

Re-encrypt all files with current key list.

**Description:**
- Find all encrypted files matching `.sops.yaml` patterns
- Re-encrypt each file using current key list
- Useful after key changes or for routine security rotation
- Show progress and summary

**Acceptance Criteria:**
- [ ] `rails sops:rotate` re-encrypts all credential files
- [ ] Files remain decryptable by authorized keys
- [ ] SOPS metadata (mac, etc.) is updated
- [ ] Shows count of files processed
- [ ] Handles empty file list gracefully

---

### Stage 3 Definition of Done

- [ ] All acceptance criteria pass
- [ ] Test: add key → decrypt with new key succeeds
- [ ] Test: remove key → decrypt with old key fails
- [ ] `.sops.yaml` manipulation is robust (preserves formatting, comments where possible)
- [ ] Operations are atomic (rollback on error)

---

## Stage 4: Production Deployment — Environment Support 🚀

**Goal:** Support production deployments where secrets are pre-decrypted by external processes.

**Value Delivered:** Complete development-to-production workflow. The gem works in development (live decryption) and production (pre-decrypted files), supporting Kubernetes, Docker, and traditional deployment patterns.

### Features

#### 4.1 Production Mode (Decrypted Files)

Read from pre-decrypted plain YAML files in production.

**Description:**
- Add `decrypted_path` config option
- Default: `ENV['DECRYPTED_SECRETS_PATH'] || '/app/secrets'` (prod) or `nil` (dev)
- Auto-detect mode based on environment and path existence
- Read plain YAML files (no SOPS needed in production container)

**Acceptance Criteria:**
- [ ] In production with `DECRYPTED_SECRETS_PATH=/app/secrets`, reads from that path
- [ ] Reads `credentials.yaml` (not `.enc`) from decrypted path
- [ ] `Sops.decrypted_mode?` returns `true` when reading plain files
- [ ] `Sops.encrypted_mode?` returns `true` when using SOPS decryption
- [ ] No SOPS binary required in production when using decrypted mode
- [ ] Falls back to encrypted mode if decrypted path doesn't exist

---

#### 4.2 Environment-Specific Credentials

Support environment overrides with deep merge.

**Description:**
- Load base credentials first, then environment-specific
- Deep merge: environment values override base values
- Default pattern: `['credentials.yaml.enc', "credentials.#{Rails.env}.yaml.enc"]`
- Skip missing environment files silently

**Acceptance Criteria:**
- [ ] `Sops.credentials` merges base + environment files
- [ ] Later files override earlier files (environment wins)
- [ ] Deep merge: base `{a: {b: 1, c: 2}}` + env `{a: {b: 9}}` = `{a: {b: 9, c: 2}}`
- [ ] Missing environment file doesn't cause error
- [ ] Works in both encrypted and decrypted modes
- [ ] `config.credential_files` allows custom file list

---

#### 4.3 Production Safety

Fail fast when secrets are missing in production.

**Description:**
- Add `require_secrets_in_production` config (default: `true`)
- Raise `Sops::NoSecretsError` if no credentials found in production
- Include helpful debugging information in error message
- Allow disabling for specific use cases

**Acceptance Criteria:**
- [ ] Raises `Sops::NoSecretsError` in production if no secrets found
- [ ] Error message includes: checked paths, environment, suggestions
- [ ] `config.require_secrets_in_production = false` disables check
- [ ] Check runs on first `Sops.credentials` access
- [ ] Does not raise in development/test environments

---

#### 4.4 Credential Caching

Cache parsed credentials for performance.

**Description:**
- Add `cache_credentials` config option
- Default: `true` in production, `false` in development
- Cache parsed credentials after first load
- Provide `Sops.reload!` method to clear cache

**Acceptance Criteria:**
- [ ] Credentials parsed once and cached when enabled
- [ ] Subsequent `Sops.credentials` calls return cached object
- [ ] `Sops.reload!` clears cache and reloads from source
- [ ] Default is `true` in production, `false` in development
- [ ] Cache respects environment (reloads pick up env-specific files)

---

#### 4.5 Rake Task: `sops:verify`

Verify configuration and setup.

**Description:**
- Check SOPS binary presence and version
- Check age binary presence and version
- Validate `.sops.yaml` syntax and rules
- Test private key accessibility
- Attempt decryption of all credential files
- Output pass/fail report

**Acceptance Criteria:**
- [ ] `rails sops:verify` runs all checks
- [ ] Shows ✓ for passing checks, ✗ for failing
- [ ] Checks: sops binary, age binary, .sops.yaml, private key, decryption
- [ ] Exit code 0 if all pass, 1 if any fail
- [ ] Each failure includes actionable solution hint

---

### Stage 4 Definition of Done

- [ ] All acceptance criteria pass
- [ ] Test: development mode with live SOPS decryption
- [ ] Test: production mode with mounted plain files
- [ ] Test: environment override merging
- [ ] Test: missing secrets error in production
- [ ] Documentation for Kubernetes/Docker deployment

---

## Stage 5: Extended Features — Integrations & Polish 🔌

**Goal:** Provide Rails credentials compatibility, .env file support, and enhanced API.

**Value Delivered:** Drop-in migration path from Rails credentials, support for teams using .env patterns, and a polished developer experience with comprehensive error handling.

### Features

#### 5.1 Enhanced Credentials API

Extend credentials access with more methods.

**Description:**
- Add `fetch` method that raises on missing key
- Add boolean predicate methods: `credentials.aws?`
- Add `to_h` method for raw hash access
- Improve nil handling consistency

**Acceptance Criteria:**
- [ ] `Sops.credentials.fetch(:aws)` returns value or raises `KeyError`
- [ ] `Sops.credentials.fetch(:missing, 'default')` returns default
- [ ] `Sops.credentials.aws?` returns `true` if key exists
- [ ] `Sops.credentials.missing?` returns `false`
- [ ] `Sops.credentials.to_h` returns plain Ruby hash with symbol keys
- [ ] Chained missing keys return `nil`: `credentials.a.b.c` → `nil`

---

#### 5.2 Rails Credentials Compatibility

Enable drop-in replacement for Rails credentials.

**Description:**
- Implement `Sops.override_rails_credentials!` method
- Monkey-patch `Rails.application.credentials` to delegate to Sops
- Allow gradual migration from Rails credentials
- Document limitations and differences

**Acceptance Criteria:**
- [ ] After `Sops.override_rails_credentials!`, `Rails.application.credentials` works
- [ ] `Rails.application.credentials.aws.access_key_id` returns sops value
- [ ] `Rails.application.credentials.dig(:aws, :key)` works
- [ ] Override can be called from initializer
- [ ] Original Rails credentials accessible if needed

---

#### 5.3 Dotenv File Support

Support SOPS-encrypted .env files.

**Description:**
- Add `env_files` config option
- Add `Sops.env` accessor for env-file values
- Support `dotenv_integration` option to inject into `ENV`
- Parse KEY=VALUE format (not YAML)

**Acceptance Criteria:**
- [ ] `config.env_files = ['.env.enc', '.env.production.enc']` loads files
- [ ] `Sops.env[:DATABASE_URL]` returns value from encrypted .env
- [ ] `Sops.env['DATABASE_URL']` works (string keys)
- [ ] With `dotenv_integration: true`, values populate `ENV`
- [ ] Supports both encrypted mode (SOPS) and decrypted mode (plain files)
- [ ] Handles comments and empty lines in .env files

---

#### 5.4 Enhanced Error Messages

Improve error handling and user experience.

**Description:**
- Add colored terminal output for Rake tasks
- Progress indicators for long operations (re-encryption)
- Context-aware error messages with solutions
- Optional debug logging

**Acceptance Criteria:**
- [ ] Rake tasks use colors (green ✓, red ✗, yellow warnings)
- [ ] Re-encryption shows progress: "Re-encrypting 3 files..."
- [ ] Errors include: what failed, why, how to fix
- [ ] `SOPS_RAILS_DEBUG=1` enables verbose logging
- [ ] Colors disabled when not TTY (CI-friendly)

---

#### 5.5 CI/CD Integration

Support non-interactive and scripting use cases.

**Description:**
- Add `--yes` / `--non-interactive` flags to confirmation prompts
- Add `--quiet` flag to suppress non-essential output
- Return appropriate exit codes for scripting
- Document GitHub Actions / GitLab CI examples

**Acceptance Criteria:**
- [ ] `rails sops:removekey KEY --yes` skips confirmation
- [ ] `rails sops:init --non-interactive` uses defaults
- [ ] `rails sops:verify --quiet` outputs only errors
- [ ] Exit code 0 = success, 1 = error, 2 = warning
- [ ] All tasks work without TTY

---

### Stage 5 Definition of Done

- [ ] All acceptance criteria pass
- [ ] Test: Rails credentials override with existing app
- [ ] Test: .env file parsing and ENV injection
- [ ] CI workflow example in documentation
- [ ] Comprehensive error message coverage

---

## Stage 6: Documentation & Release Readiness 📚

**Goal:** Prepare the gem for public release with comprehensive documentation.

**Value Delivered:** Enterprise-ready reliability, developer-friendly documentation, and confidence for production use.

### Features

#### 6.1 YARD Documentation

Document all public APIs.

**Description:**
- Add YARD docstrings to all public methods
- Include usage examples in documentation
- Generate browsable HTML documentation
- Document configuration options with defaults

**Acceptance Criteria:**
- [ ] `yard doc` generates documentation without warnings
- [ ] All public methods have `@param` and `@return` tags
- [ ] All public methods have usage `@example`
- [ ] Configuration options documented with defaults
- [ ] `@raise` tags for methods that can raise exceptions

---

#### 6.2 README & Guides

Update README and create deployment guides.

**Description:**
- Keep README comprehensive but scannable
- Create separate deployment guide documents
- Migration guide from Rails credentials
- Troubleshooting guide with common issues

**Acceptance Criteria:**
- [ ] README has: Quick Start, Configuration, API Reference
- [ ] Kubernetes deployment guide with Flux/ArgoCD examples
- [ ] Docker Compose deployment guide
- [ ] Traditional VPS deployment guide
- [ ] Migration guide tested with real Rails app

---

#### 6.3 Test Coverage

Ensure comprehensive test coverage.

**Description:**
- Unit tests for all modules
- Integration tests with real SOPS/age binaries
- CI matrix: multiple Ruby versions, multiple Rails versions
- Edge case coverage (missing files, permissions, etc.)

**Acceptance Criteria:**
- [ ] Test coverage > 90% for non-trivial code
- [ ] CI runs on Ruby 3.0, 3.1, 3.2, 3.3
- [ ] CI runs on Rails 7.0, 7.1, 7.2
- [ ] Integration tests use real SOPS binary
- [ ] Tests for error conditions and edge cases

---

#### 6.4 Release Preparation

Prepare for RubyGems release.

**Description:**
- Finalize gem metadata (description, homepage, etc.)
- Set up GitHub Actions for CI and release
- Create CHANGELOG with all features
- Tag version and publish to RubyGems

**Acceptance Criteria:**
- [ ] `bundle exec rake build` creates valid gem
- [ ] `bundle exec rake release` publishes to RubyGems
- [ ] CHANGELOG.md documents all features and changes
- [ ] GitHub releases created with release notes
- [ ] Gem installable via `gem install sops-rails`

---

### Stage 6 Definition of Done

- [ ] All acceptance criteria pass
- [ ] Documentation review by someone unfamiliar with project
- [ ] Test suite passes on CI
- [ ] Gem published and installable
- [ ] README badges show passing CI

---

## Technical Debt

Items to address when time permits:

### TD-1: Code Duplication in Rake Task Argument Parsing

`SopsShowTask` and `SopsEditTask` modules in `lib/sops_rails/tasks/sops.rake` are nearly identical. The only difference is the task name used in `extract_task_args`. Consider refactoring to a shared base module or extracting a `TaskArgumentParser` class.

**Files affected:**
- `lib/sops_rails/tasks/sops.rake` (lines ~8-117)

**Suggested approach:**
- Create `SopsTaskHelper` base module with configurable task name
- Or extract shared methods and DRY up both modules

---

## Implementation Order & Dependencies

```
┌─────────────────────────────────────────────────────────────────┐
│  Stage 1: Core MVP                                              │
│  ├── 1.1 Configuration Module                                   │
│  ├── 1.2 SOPS Binary Interface                                  │
│  ├── 1.3 Credentials Reader                                     │
│  └── 1.4 Rails Integration                                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 2: Developer Workflow                                    │
│  ├── 2.1 sops:show                                              │
│  ├── 2.2 sops:edit                                              │
│  ├── 2.3 sops:init                                              │
│  └── 2.4 .sops.yaml Template                                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 3: Team Collaboration                                    │
│  ├── 3.1 sops:keys                                              │
│  ├── 3.2 sops:addkey                                            │
│  ├── 3.3 sops:removekey                                         │
│  └── 3.4 sops:rotate                                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 4: Production Deployment                                 │
│  ├── 4.1 Production Mode                                        │
│  ├── 4.2 Environment-Specific Credentials                       │
│  ├── 4.3 Production Safety                                      │
│  ├── 4.4 Credential Caching                                     │
│  └── 4.5 sops:verify                                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 5: Extended Features                                     │
│  ├── 5.1 Enhanced Credentials API                               │
│  ├── 5.2 Rails Credentials Compatibility                        │
│  ├── 5.3 Dotenv File Support                                    │
│  ├── 5.4 Enhanced Error Messages                                │
│  └── 5.5 CI/CD Integration                                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 6: Documentation & Release                               │
│  ├── 6.1 YARD Documentation                                     │
│  ├── 6.2 README & Guides                                        │
│  ├── 6.3 Test Coverage                                          │
│  └── 6.4 Release Preparation                                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Milestone Summary

| Stage | Goal | Key Deliverable | Est. Effort |
|-------|------|-----------------|-------------|
| **1** | Core MVP | `Sops.credentials.key` works | Small |
| **2** | Developer Workflow | `sops:init`, `sops:edit` work | Medium |
| **3** | Team Collaboration | Add/remove keys, re-encrypt | Medium |
| **4** | Production Support | Environment files, prod mode | Medium |
| **5** | Extended Features | Rails compat, .env, polish | Medium |
| **6** | Release Readiness | Docs, tests, publish | Medium |

---

## Success Criteria Per Stage

| Stage | Success = |
|-------|-----------|
| 1 | Developer reads encrypted secret in Rails console |
| 2 | Developer initializes and edits credentials without touching SOPS directly |
| 3 | Team member added/removed with working access control |
| 4 | App boots in production with externally-decrypted secrets |
| 5 | Existing app migrates from Rails credentials with minimal changes |
| 6 | New developer sets up in <5 minutes using documentation |

---

## Risk Mitigation

| Risk | Mitigation Strategy |
|------|---------------------|
| SOPS binary version incompatibility | Test against 3.7.x and 3.8.x; document minimum version |
| Age key path varies across OS | Support `SOPS_AGE_KEY_FILE`, `SOPS_AGE_KEY`, and standard paths |
| Editor integration issues | Delegate to SOPS native edit; test with vim, nano, VS Code |
| Production path permissions | Clear error messages; document K8s volume mounts |
| Deep merge edge cases | Use `Hash#deep_merge` from ActiveSupport; comprehensive tests |

---

## Notes

- **Branch Strategy:** Each stage gets a feature branch; merge to main when complete
- **Testing:** Integration tests require SOPS + age binaries in CI (use setup action)
- **Backwards Compatibility:** After Stage 1 release, maintain API stability
- **Debug Mode:** `SOPS_RAILS_DEBUG=1` environment variable for troubleshooting
- **Version Strategy:** Stage 1 = 0.1.0, Stage 2 = 0.2.0, ..., Stage 6 = 1.0.0
