# sops-rails

Native [SOPS](https://github.com/getsops/sops) encryption support for Rails applications. Manage your secrets with visible structure, team-friendly key rotation, and Kubernetes-native workflows.

[![Gem Version](https://badge.fury.io/rb/sops-rails.svg)](https://rubygems.org/gems/sops-rails)
[![CI](https://github.com/your-org/sops-rails/actions/workflows/ci.yml/badge.svg)](https://github.com/your-org/sops-rails/actions)

## Why sops-rails?

Rails' built-in encrypted credentials work well for small teams, but they have limitations:

| Challenge | Rails Credentials | sops-rails |
|-----------|------------------|------------|
| **Visibility** | Fully encrypted blob — can't see structure without decrypting | Only values encrypted — `git diff` shows "added `stripe.webhook_secret`" |
| **Key sharing** | Pass `master.key` file around (Slack, 1Password, etc.) | Each developer has their own age key; add/remove via CLI |
| **Key rotation** | Re-encrypt everything, redistribute new key | Add new key, re-encrypt, remove old key — no coordination needed |
| **Production security** | `master.key` must exist in container | Private key never touches application container |
| **GitOps/K8s** | Requires custom tooling | Native SOPS support in Flux, ArgoCD, Helm Secrets |

### When to use sops-rails

**Great fit:**
- Teams using Kubernetes, Flux, or ArgoCD for deployments
- Organizations requiring audit trails for secret changes
- Multi-environment setups with different access levels
- Teams frustrated with `master.key` distribution

**Consider alternatives if:**
- You're a solo developer on Heroku — Rails credentials are simpler
- Your team has no familiarity with SOPS or age encryption
- You need secrets available without any external tooling

## Installation

Add to your Gemfile:

```ruby
gem 'sops-rails'
```

Then run:

```bash
bundle install
rails sops:init
```

### Prerequisites

**SOPS** (v3.8.0 or later):
```bash
# macOS
brew install sops

# Debian/Ubuntu
apt install sops

# Or download from https://github.com/getsops/sops/releases
```

**age** (recommended over PGP for simplicity):
```bash
# macOS
brew install age

# Debian/Ubuntu
apt install age
```

## Quick Start

### 1. Initialize sops-rails

```bash
rails sops:init
```

This will:
- Generate your personal age key pair (if needed)
- Create `.sops.yaml` with Rails-friendly defaults
- Add appropriate entries to `.gitignore`
- Create initial `config/credentials.yaml.enc`

### 2. Edit your credentials

```bash
rails sops:edit
```

Your editor opens with decrypted YAML:

```yaml
# config/credentials.yaml.enc (decrypted view)
aws:
  access_key_id: AKIAIOSFODNN7EXAMPLE
  secret_access_key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

stripe:
  secret_key: sk_live_xxx
  webhook_secret: whsec_xxx

database:
  password: supersecret
```

Save and close — the file is automatically re-encrypted.

### 3. Access credentials in your app

```ruby
# Anywhere in your Rails app
Sops.credentials.aws.access_key_id
# => "AKIAIOSFODNN7EXAMPLE"

Sops.credentials.dig(:stripe, :webhook_secret)
# => "whsec_xxx"

# In database.yml
password: <%= Sops.credentials.database.password %>
```

## How It Works

### Development

```
┌─────────────────────────────────────────────────────────┐
│                    Development                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   config/credentials.yaml.enc ──► sops -d (in memory)  │
│            (encrypted)                    │             │
│                                           ▼             │
│                                   Sops.credentials      │
│                                                         │
│   Private key: ~/.config/sops/age/keys.txt             │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

In development, the gem shells out to `sops -d` and parses the decrypted YAML **in memory**. No decrypted files are ever written to disk, eliminating the risk of accidentally committing secrets.

### Production

```
┌─────────────────────────────────────────────────────────┐
│                     Production                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   External decryption          Plain YAML files         │
│   (init container, Flux,  ──►  /app/secrets/*.yaml     │
│    entrypoint script)                  │                │
│                                        ▼                │
│                                Sops.credentials         │
│                                                         │
│   Private key: NEVER in application container           │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

In production, secrets are decrypted **before** the Rails application starts by an external process. The gem simply reads plain YAML files from a configured path. The private key never exists in the running application container.

## Configuration

### Basic Configuration

```ruby
# config/initializers/sops.rb
Sops.configure do |config|
  # Path where decrypted secrets are mounted in production
  # Default: ENV['DECRYPTED_SECRETS_PATH'] || '/app/secrets' (prod) || 'tmp/secrets' (dev)
  config.decrypted_path = '/app/secrets'

  # Path to encrypted credentials in repo
  # Default: 'config'
  config.encrypted_path = 'config'

  # File patterns to load (order matters — later files override earlier)
  # Default: ['credentials.yaml.enc', "credentials.#{Rails.env}.yaml.enc"]
  config.credential_files = [
    'credentials.yaml.enc',
    "credentials.#{Rails.env}.yaml.enc"
  ]

  # Fail loudly if no secrets found in production
  # Default: true
  config.require_secrets_in_production = true

  # Cache decrypted credentials (recommended)
  # Default: true in production, false in development
  config.cache_credentials = Rails.env.production?
end
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DECRYPTED_SECRETS_PATH` | Path to decrypted secrets in production | `/app/secrets` |
| `SOPS_AGE_KEY_FILE` | Path to age private key (development) | `~/.config/sops/age/keys.txt` |
| `SOPS_AGE_KEY` | Age private key contents (alternative to file) | — |

### ENV File Support

sops-rails supports encrypted `.env` files alongside YAML credentials.

#### Option A: Dotenv Integration (Recommended)

Automatically loads decrypted env vars into `ENV`:

```ruby
# config/initializers/sops.rb
Sops.configure do |config|
  config.dotenv_integration = true
  config.env_files = ['.env.enc', ".env.#{Rails.env}.enc"]
end
```

```bash
# .env.production.enc (encrypted)
DATABASE_URL=ENC[AES256_GCM,data:xxx,tag:xxx]
REDIS_URL=ENC[AES256_GCM,data:xxx,tag:xxx]
```

After loading:
```ruby
ENV['DATABASE_URL'] # => "postgres://..."
```

#### Option B: Explicit Namespace

Keep env vars separate from `ENV` for explicit access:

```ruby
# config/initializers/sops.rb
Sops.configure do |config|
  config.dotenv_integration = false  # default
end
```

```ruby
# Access via Sops.env
Sops.env[:DATABASE_URL]  # => "postgres://..."
Sops.env['REDIS_URL']    # => "redis://..."

# ENV is not modified
ENV['DATABASE_URL']      # => nil (unless set elsewhere)
```

## Rake Commands

### `rails sops:init`

Interactive setup wizard:

```bash
$ rails sops:init

🔐 sops-rails setup
═══════════════════

Checking prerequisites...
  ✓ sops 3.8.1 found
  ✓ age 1.1.1 found

Age key setup:
  No existing key found at ~/.config/sops/age/keys.txt
  ? Generate a new age key pair? [Y/n] y
  ✓ Generated key pair

  Your public key (share this with your team):
  age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p

Creating .sops.yaml...
  ✓ Created .sops.yaml with Rails defaults

Updating .gitignore...
  ✓ Added sops-rails entries

Creating initial credentials file...
  ? Create config/credentials.yaml.enc? [Y/n] y
  ✓ Created encrypted credentials file

🎉 Setup complete!

Next steps:
  1. Edit credentials:     rails sops:edit
  2. Add team member:      rails sops:addkey AGE_PUBLIC_KEY
  3. View current keys:    rails sops:keys
```

### `rails sops:edit [FILE]`

Edit encrypted credentials:

```bash
# Edit base credentials
rails sops:edit

# Edit environment-specific credentials
rails sops:edit -e production
rails sops:edit config/credentials.production.yaml.enc

# Edit env file
rails sops:edit .env.production.enc
```

Uses `$EDITOR` (falls back to `vim`, then `nano`).

### `rails sops:show [FILE]`

Display decrypted contents without editing:

```bash
rails sops:show
rails sops:show -e production
```

### `rails sops:addkey PUBLIC_KEY [--name NAME]`

Add a team member's public key:

```bash
$ rails sops:addkey age1abc123... --name "Alice (alice@example.com)"

Adding key to .sops.yaml...
  ✓ Added key: Alice (alice@example.com)

Re-encrypting files with new key...
  ✓ config/credentials.yaml.enc
  ✓ config/credentials.production.yaml.enc
  ✓ .env.production.enc

✓ Key added successfully
  Alice can now decrypt all credentials.
```

### `rails sops:removekey PUBLIC_KEY`

Remove a team member's access:

```bash
$ rails sops:removekey age1abc123...

⚠️  Warning: This will remove access for key age1abc123...
   Found in .sops.yaml as: Alice (alice@example.com)

? Continue? [y/N] y

Removing key from .sops.yaml...
  ✓ Removed key

Re-encrypting files without removed key...
  ✓ config/credentials.yaml.enc
  ✓ config/credentials.production.yaml.enc
  ✓ .env.production.enc

✓ Key removed successfully
  This key can no longer decrypt credentials.

⚠️  Note: If this key had access to secrets, consider rotating them.
```

### `rails sops:keys`

List all authorized keys:

```bash
$ rails sops:keys

Authorized age keys:
  1. age1ql3z7hjy... — Tom (tom@example.com)
  2. age1abc1234... — Alice (alice@example.com)
  3. age1xyz5678... — CI/CD (GitHub Actions)
```

### `rails sops:rotate`

Re-encrypt all files (useful after key changes):

```bash
rails sops:rotate
```

### `rails sops:verify`

Verify your setup is correct:

```bash
$ rails sops:verify

Checking sops-rails configuration...
  ✓ sops binary found (v3.8.1)
  ✓ age binary found (v1.1.1)
  ✓ .sops.yaml exists and valid
  ✓ Private key accessible
  ✓ Can decrypt config/credentials.yaml.enc
  ✓ Can decrypt config/credentials.production.yaml.enc

All checks passed!
```

## Usage Examples

### Basic Credentials Access

```ruby
# Using method chaining (returns nil for missing keys)
Sops.credentials.aws.access_key_id
Sops.credentials.stripe.secret_key

# Using dig (safe navigation)
Sops.credentials.dig(:aws, :access_key_id)

# Using fetch (raises on missing key)
Sops.credentials.fetch(:aws).fetch(:access_key_id)

# Check if key exists
Sops.credentials.aws? # => true/false

# Get raw hash
Sops.credentials.to_h
# => { aws: { access_key_id: "...", secret_access_key: "..." }, ... }
```

### In database.yml

```yaml
# config/database.yml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

production:
  <<: *default
  url: <%= Sops.credentials.database.url %>
  # Or individual components:
  # host: <%= Sops.credentials.database.host %>
  # password: <%= Sops.credentials.database.password %>
```

### In Initializers

```ruby
# config/initializers/stripe.rb
Stripe.api_key = Sops.credentials.stripe.secret_key

# config/initializers/aws.rb
Aws.config.update(
  credentials: Aws::Credentials.new(
    Sops.credentials.aws.access_key_id,
    Sops.credentials.aws.secret_access_key
  )
)
```

### Environment-Specific Overrides

```yaml
# config/credentials.yaml.enc (base)
database:
  pool: 5

stripe:
  secret_key: sk_test_xxx  # test key as default
```

```yaml
# config/credentials.production.yaml.enc
database:
  pool: 25

stripe:
  secret_key: sk_live_xxx  # production key
```

```ruby
# In production, production values override base:
Sops.credentials.stripe.secret_key  # => "sk_live_xxx"
Sops.credentials.database.pool      # => 25
```

### Checking Environment

```ruby
# In production, credentials are loaded from pre-decrypted files
if Sops.decrypted_mode?
  Rails.logger.info "Loading credentials from #{Sops.config.decrypted_path}"
end

# In development, credentials are decrypted on-the-fly
if Sops.encrypted_mode?
  Rails.logger.info "Decrypting credentials via sops CLI"
end
```

### Rails Credentials Compatibility

For gradual migration, you can make `Rails.application.credentials` use sops-rails:

```ruby
# config/initializers/sops.rb
Sops.override_rails_credentials!

# Now both work:
Rails.application.credentials.aws.access_key_id
Sops.credentials.aws.access_key_id
```

## Deployment Strategies

### Strategy 1: Kubernetes with Flux SOPS (Recommended)

Flux can decrypt SOPS-encrypted secrets at deploy time. This is the most GitOps-native approach.

**Setup:**

1. Create an age key for Flux:
```bash
age-keygen -o flux.agekey
# Public key: age1xxx...
```

2. Add Flux's public key to your `.sops.yaml`:
```bash
rails sops:addkey age1xxx... --name "Flux (production cluster)"
```

3. Create a Kubernetes secret with Flux's private key:
```bash
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=flux.agekey
```

4. Configure Flux Kustomization to decrypt:
```yaml
# clusters/production/kustomization.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: my-app
  namespace: flux-system
spec:
  # ... other config
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

5. Store encrypted credentials as a Kubernetes Secret manifest:
```yaml
# config/deploy/secrets.yaml.enc
apiVersion: v1
kind: Secret
metadata:
  name: app-credentials
type: Opaque
stringData:
  credentials.yaml: |
    aws:
      access_key_id: ENC[AES256_GCM,data:xxx]
      secret_access_key: ENC[AES256_GCM,data:xxx]
    stripe:
      secret_key: ENC[AES256_GCM,data:xxx]
```

6. Mount in your deployment:
```yaml
# config/deploy/deployment.yaml
spec:
  containers:
    - name: app
      env:
        - name: DECRYPTED_SECRETS_PATH
          value: /app/secrets
      volumeMounts:
        - name: credentials
          mountPath: /app/secrets
          readOnly: true
  volumes:
    - name: credentials
      secret:
        secretName: app-credentials
```

**Security:** Private key exists only in `flux-system` namespace, never in application pods.

### Strategy 2: Kubernetes Init Container

For clusters without Flux SOPS support.

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      initContainers:
        - name: decrypt-secrets
          image: mozilla/sops:v3.8.1-alpine
          command:
            - sh
            - -c
            - |
              sops -d /encrypted/credentials.yaml.enc > /secrets/credentials.yaml
              sops -d /encrypted/credentials.production.yaml.enc > /secrets/credentials.production.yaml
          env:
            - name: SOPS_AGE_KEY
              valueFrom:
                secretKeyRef:
                  name: sops-age-key
                  key: age.key
          volumeMounts:
            - name: encrypted-credentials
              mountPath: /encrypted
            - name: decrypted-secrets
              mountPath: /secrets

      containers:
        - name: app
          image: my-app:latest
          env:
            - name: DECRYPTED_SECRETS_PATH
              value: /app/secrets
          volumeMounts:
            - name: decrypted-secrets
              mountPath: /app/secrets
              readOnly: true

      volumes:
        - name: encrypted-credentials
          configMap:
            name: encrypted-credentials
        - name: decrypted-secrets
          emptyDir:
            medium: Memory  # tmpfs — never written to disk
```

**Security:** Private key exists only in init container, not in application container. Decrypted secrets live in memory-backed emptyDir.

### Strategy 3: Docker Compose

For simpler deployments or staging environments.

**Option A: Entrypoint script (key in container)**

```dockerfile
# Dockerfile
FROM ruby:3.3-slim

# Install sops
RUN curl -LO https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64 \
    && mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops \
    && chmod +x /usr/local/bin/sops

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["rails", "server"]
```

```bash
#!/bin/bash
# docker-entrypoint.sh
set -e

# Decrypt secrets before starting Rails
if [ -n "$SOPS_AGE_KEY" ]; then
  mkdir -p /app/secrets
  sops -d config/credentials.yaml.enc > /app/secrets/credentials.yaml

  if [ -f "config/credentials.${RAILS_ENV}.yaml.enc" ]; then
    sops -d "config/credentials.${RAILS_ENV}.yaml.enc" > "/app/secrets/credentials.${RAILS_ENV}.yaml"
  fi
fi

exec "$@"
```

```yaml
# docker-compose.yml
services:
  web:
    build: .
    environment:
      RAILS_ENV: production
      SOPS_AGE_KEY: ${SOPS_AGE_KEY}  # From .env or CI secret
      DECRYPTED_SECRETS_PATH: /app/secrets
```

⚠️ **Note:** This approach means the private key exists in the container environment. Use only when infrastructure doesn't support external decryption.

**Option B: Sidecar decryption (key isolated)**

```yaml
# docker-compose.yml
services:
  decrypt:
    image: mozilla/sops:v3.8.1-alpine
    command: >
      sh -c "sops -d /encrypted/credentials.yaml.enc > /secrets/credentials.yaml &&
             sops -d /encrypted/credentials.production.yaml.enc > /secrets/credentials.production.yaml &&
             sleep infinity"
    environment:
      SOPS_AGE_KEY: ${SOPS_AGE_KEY}
    volumes:
      - ./config:/encrypted:ro
      - secrets:/secrets

  web:
    build: .
    depends_on:
      - decrypt
    environment:
      RAILS_ENV: production
      DECRYPTED_SECRETS_PATH: /secrets
    volumes:
      - secrets:/secrets:ro

volumes:
  secrets:
```

### Strategy 4: Dokku

#### Option A: Without private key in container (Recommended)

Use a pre-deploy script to decrypt secrets before the app builds:

```bash
# On Dokku server, create a plugin or use dokku-preboot
# /var/lib/dokku/plugins/available/sops-decrypt/pre-deploy

#!/bin/bash
set -e
APP="$1"

# Age key stored securely on Dokku server
export SOPS_AGE_KEY_FILE=/home/dokku/.config/sops/age/keys.txt

cd /home/dokku/$APP

# Decrypt to persistent storage
mkdir -p /var/lib/dokku/data/storage/$APP/secrets
sops -d config/credentials.yaml.enc > /var/lib/dokku/data/storage/$APP/secrets/credentials.yaml

if [ -f "config/credentials.production.yaml.enc" ]; then
  sops -d config/credentials.production.yaml.enc > /var/lib/dokku/data/storage/$APP/secrets/credentials.production.yaml
fi
```

Configure storage mount:
```bash
dokku storage:mount my-app /var/lib/dokku/data/storage/my-app/secrets:/app/secrets
dokku config:set my-app DECRYPTED_SECRETS_PATH=/app/secrets
```

**Security:** Private key exists only on Dokku server, never in container.

#### Option B: With private key in container

Simpler but less secure — use when you can't modify Dokku plugins:

```bash
# Set age key as environment variable
dokku config:set my-app SOPS_AGE_KEY="AGE-SECRET-KEY-1..."
```

```ruby
# config/initializers/sops.rb
Sops.configure do |config|
  # In Dokku with key in env, decrypt on boot
  if ENV['SOPS_AGE_KEY'].present? && !File.exist?('/app/secrets/credentials.yaml')
    config.decrypt_on_boot = true
  end
end
```

### Strategy 5: Traditional VPS / Bare Metal

Decrypt during deployment with Capistrano, Ansible, or similar:

```ruby
# config/deploy.rb (Capistrano)
namespace :sops do
  desc 'Decrypt secrets'
  task :decrypt do
    on roles(:app) do
      within release_path do
        execute :mkdir, '-p', 'tmp/secrets'
        execute :sops, '-d', 'config/credentials.yaml.enc', '>', 'tmp/secrets/credentials.yaml'
        execute :sops, '-d', "config/credentials.#{fetch(:rails_env)}.yaml.enc",
                '>', "tmp/secrets/credentials.#{fetch(:rails_env)}.yaml"
      end
    end
  end
end

before 'deploy:assets:precompile', 'sops:decrypt'
```

## Security Considerations

### Design Decisions

1. **Memory-only decryption in development**

   The gem never writes decrypted files to disk during development. When you run `rails sops:edit`, the decrypted content goes directly to your editor's stdin and the re-encrypted output comes from stdout. This eliminates the risk of accidentally committing decrypted secrets.

2. **Private key isolation in production**

   The gem is designed so the application container never needs the private key. Decryption happens externally (init container, Flux, entrypoint), and the app only reads plain files.

3. **Fail-fast in production**

   If credentials are missing in production, the app raises `Sops::NoSecretsError` immediately rather than silently continuing with nil values.

### Recommendations

- **Rotate secrets after removing team member access** — removing their key prevents future decryption, but they may have copied secrets already
- **Use separate keys for CI/CD** — if compromised, revoke only that key
- **Audit `.sops.yaml` in code review** — key additions/removals should be visible
- **Never commit `.env` or `*.decrypted.*` files** — the gem adds these to `.gitignore` automatically
- **Consider separate keys per environment** — production secrets accessible only to production key

### What sops-rails Does NOT Do

- Does not implement any cryptography (delegates to `sops` binary)
- Does not store or manage private keys (uses age's standard key locations)
- Does not transmit secrets over network (local file operations only)
- Does not provide access control within the app (all secrets available to all code)

## File Structure

After setup, your project will have:

```
my-rails-app/
├── .sops.yaml                              # SOPS configuration (keys, rules)
├── .gitignore                              # Updated with sops-rails entries
├── config/
│   ├── credentials.yaml.enc               # Base credentials (encrypted)
│   ├── credentials.development.yaml.enc   # Dev overrides (encrypted, optional)
│   ├── credentials.production.yaml.enc    # Prod overrides (encrypted)
│   └── initializers/
│       └── sops.rb                        # sops-rails configuration
├── .env.production.enc                    # Encrypted env file (optional)
└── tmp/
    └── secrets/                           # Dev: never used (memory-only)
                                           # Prod: mount point for decrypted files
```

### `.sops.yaml` Example

```yaml
creation_rules:
  # Rails credentials
  - path_regex: config/credentials\..*\.yaml\.enc$
    age:
      - age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p  # Tom
      - age1abc123...  # Alice
      - age1xyz789...  # CI/CD

  # Env files
  - path_regex: \.env\..*\.enc$
    age:
      - age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
      - age1abc123...
      - age1xyz789...

  # Catch-all: fail loudly rather than encrypt with unknown key
  - path_regex: .*
    age: ""
```

## Troubleshooting

### "sops binary not found"

```bash
# Install sops
brew install sops        # macOS
apt install sops         # Debian/Ubuntu

# Verify
sops --version
```

### "No age identity found"

```bash
# Generate a new key
age-keygen -o ~/.config/sops/age/keys.txt

# Or set via environment
export SOPS_AGE_KEY="AGE-SECRET-KEY-1..."
```

### "Could not decrypt file"

Your key isn't in the file's authorized keys list. Ask a team member to add your key:

```bash
# Share your public key
cat ~/.config/sops/age/keys.txt | grep "public key:"

# Team member runs
rails sops:addkey age1yourpublickey...
```

### "No secrets found in production"

Check that:
1. `DECRYPTED_SECRETS_PATH` is set correctly
2. Decrypted files exist at that path
3. Files are readable by the Rails process

```ruby
# Debug in rails console
Sops.config.decrypted_path  # => "/app/secrets"
Dir.glob("#{Sops.config.decrypted_path}/*")  # => ["credentials.yaml", ...]
```

### Credentials not updating in development

The gem caches by default in production but not development. If you've changed this:

```ruby
# Force reload
Sops.reload!

# Or disable caching in development
Sops.configure { |c| c.cache_credentials = false }
```

## Migrating from Rails Credentials

1. **Export existing credentials:**
   ```bash
   rails credentials:show > tmp/credentials_backup.yaml
   ```

2. **Initialize sops-rails:**
   ```bash
   rails sops:init
   ```

3. **Copy credentials:**
   ```bash
   rails sops:edit
   # Paste contents from tmp/credentials_backup.yaml
   ```

4. **Update code references:**
   ```ruby
   # Before
   Rails.application.credentials.aws.access_key_id

   # After (option A: explicit)
   Sops.credentials.aws.access_key_id

   # After (option B: compatibility mode)
   Sops.override_rails_credentials!
   Rails.application.credentials.aws.access_key_id  # Still works
   ```

5. **Remove old credentials:**
   ```bash
   rm config/credentials.yml.enc config/master.key
   ```

## Alternatives

| Tool | Best For |
|------|----------|
| **Rails Credentials** | Small teams, simple deployments, Heroku |
| **sops-rails** | Kubernetes/GitOps, team key rotation, audit trails |
| **Vault** | Dynamic secrets, fine-grained ACLs, enterprise compliance |
| **AWS Secrets Manager** | AWS-native apps, automatic rotation |
| **dotenv + encrypted repo** | Simple apps, familiar workflow |

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/your-org/sops-rails.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).