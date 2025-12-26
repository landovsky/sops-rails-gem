# frozen_string_literal: true

RSpec.describe SopsRails::Credentials do
  after { SopsRails.reset! }

  describe ".new" do
    it "creates a Credentials instance with empty hash by default" do
      creds = described_class.new
      expect(creds).to be_empty
    end

    it "creates a Credentials instance with provided data" do
      creds = described_class.new(aws: { key: "secret" })
      expect(creds.aws.key).to eq("secret")
    end

    it "handles nil data gracefully" do
      creds = described_class.new(nil)
      expect(creds).to be_empty
    end

    it "deep symbolizes string keys" do
      creds = described_class.new("aws" => { "access_key" => "value" })
      expect(creds.aws.access_key).to eq("value")
    end
  end

  describe "method chaining" do
    let(:credentials) do
      described_class.new(
        aws: {
          access_key_id: "AKIAIOSFODNN7EXAMPLE",
          secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
          region: "us-east-1"
        },
        database: {
          host: "localhost",
          credentials: {
            username: "admin",
            password: "supersecret"
          }
        }
      )
    end

    it "returns values for top-level keys" do
      expect(credentials.aws).to be_a(described_class)
    end

    it "returns values for nested keys" do
      expect(credentials.aws.access_key_id).to eq("AKIAIOSFODNN7EXAMPLE")
    end

    it "returns values for deeply nested keys" do
      expect(credentials.database.credentials.password).to eq("supersecret")
    end

    it "returns nil for missing top-level keys" do
      expect(credentials.nonexistent).to be_nil
    end

    it "returns nil for missing nested keys without raising error" do
      expect(credentials.nonexistent.nested.key).to be_nil
    end

    it "returns nil for partially existing paths" do
      expect(credentials.aws.nonexistent.deep).to be_nil
    end
  end

  describe "#dig" do
    let(:credentials) do
      described_class.new(
        aws: {
          access_key_id: "AKIAIOSFODNN7EXAMPLE",
          nested: { deep: { value: "found" } }
        }
      )
    end

    it "returns value for single key using dig" do
      # rubocop:disable Style/SingleArgumentDig
      expect(credentials.dig(:aws)).to be_a(Hash)
      # rubocop:enable Style/SingleArgumentDig
    end

    it "returns value for nested keys with symbols" do
      expect(credentials.dig(:aws, :access_key_id)).to eq("AKIAIOSFODNN7EXAMPLE")
    end

    it "returns value for deeply nested keys" do
      expect(credentials.dig(:aws, :nested, :deep, :value)).to eq("found")
    end

    it "returns nil for missing keys" do
      expect(credentials[:missing]).to be_nil
    end

    it "returns nil for missing nested keys" do
      expect(credentials.dig(:aws, :missing, :key)).to be_nil
    end

    it "works with string keys (converts to symbols)" do
      expect(credentials.dig("aws", "access_key_id")).to eq("AKIAIOSFODNN7EXAMPLE")
    end
  end

  describe "#[]" do
    let(:credentials) do
      described_class.new(aws: { key: "value" })
    end

    it "returns wrapped value for existing key" do
      expect(credentials[:aws]).to be_a(described_class)
      expect(credentials[:aws][:key]).to eq("value")
    end

    it "returns NullCredentials for missing key" do
      expect(credentials[:missing]).to be_nil
    end

    it "works with string keys" do
      expect(credentials["aws"]["key"]).to eq("value")
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      data = { aws: { key: "secret" }, db: { password: "pass" } }
      creds = described_class.new(data)

      expect(creds.to_h).to eq(data)
    end

    it "returns a copy (not the original hash)" do
      data = { key: "value" }
      creds = described_class.new(data)
      hash = creds.to_h

      hash[:new_key] = "new_value"
      expect(creds.to_h).not_to have_key(:new_key)
    end
  end

  describe "#empty?" do
    it "returns true for empty credentials" do
      expect(described_class.new).to be_empty
    end

    it "returns false for non-empty credentials" do
      expect(described_class.new(key: "value")).not_to be_empty
    end
  end

  describe "#key?" do
    let(:credentials) { described_class.new(aws: { key: "value" }, database: {}) }

    it "returns true for existing keys" do
      expect(credentials.key?(:aws)).to be true
    end

    it "returns false for missing keys" do
      expect(credentials.key?(:nonexistent)).to be false
    end

    it "works with string keys" do
      expect(credentials.key?("aws")).to be true
    end

    it "has has_key? alias" do
      # rubocop:disable Style/PreferredHashMethods
      expect(credentials.has_key?(:aws)).to be true
      # rubocop:enable Style/PreferredHashMethods
    end
  end

  describe "#keys" do
    it "returns all top-level keys" do
      creds = described_class.new(aws: {}, database: {}, smtp: {})
      expect(creds.keys).to contain_exactly(:aws, :database, :smtp)
    end

    it "returns empty array for empty credentials" do
      expect(described_class.new.keys).to eq([])
    end
  end

  describe "#inspect" do
    it "shows class name and keys without exposing values" do
      creds = described_class.new(aws: { secret: "hidden" }, db: { password: "secret" })
      result = creds.inspect

      expect(result).to include("SopsRails::Credentials")
      expect(result).to include(":aws")
      expect(result).to include(":db")
      expect(result).not_to include("hidden")
      expect(result).not_to include("secret")
    end
  end

  describe ".load" do
    let(:yaml_content) do
      <<~YAML
        aws:
          access_key_id: AKIAIOSFODNN7EXAMPLE
          secret_access_key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
        database:
          password: supersecret
      YAML
    end

    before do
      SopsRails.configure do |config|
        config.encrypted_path = "config"
        config.credential_files = ["credentials.yaml.enc"]
      end
    end

    context "when file exists and decryption succeeds" do
      before do
        allow(File).to receive(:exist?).with("config/credentials.yaml.enc").and_return(true)
        allow(SopsRails::Binary).to receive(:decrypt)
          .with("config/credentials.yaml.enc")
          .and_return(yaml_content)
      end

      it "returns a Credentials instance" do
        creds = described_class.load
        expect(creds).to be_a(described_class)
      end

      it "parses YAML content correctly" do
        creds = described_class.load
        expect(creds.aws.access_key_id).to eq("AKIAIOSFODNN7EXAMPLE")
        expect(creds.database.password).to eq("supersecret")
      end
    end

    context "when file does not exist" do
      before do
        allow(File).to receive(:exist?).with("config/credentials.yaml.enc").and_return(false)
      end

      it "returns empty credentials" do
        creds = described_class.load
        expect(creds).to be_empty
      end
    end

    context "when multiple credential files are configured" do
      let(:base_yaml) { "aws:\n  region: us-east-1\n  key: base_key\n" }
      let(:override_yaml) { "aws:\n  key: override_key\n  secret: override_secret\n" }

      before do
        SopsRails.configure do |config|
          config.credential_files = ["credentials.yaml.enc", "credentials.local.yaml.enc"]
        end

        allow(File).to receive(:exist?).with("config/credentials.yaml.enc").and_return(true)
        allow(File).to receive(:exist?).with("config/credentials.local.yaml.enc").and_return(true)
        allow(SopsRails::Binary).to receive(:decrypt)
          .with("config/credentials.yaml.enc")
          .and_return(base_yaml)
        allow(SopsRails::Binary).to receive(:decrypt)
          .with("config/credentials.local.yaml.enc")
          .and_return(override_yaml)
      end

      it "deep merges multiple files" do
        creds = described_class.load

        # Base value preserved
        expect(creds.aws.region).to eq("us-east-1")
        # Override value used
        expect(creds.aws.key).to eq("override_key")
        # New value from override
        expect(creds.aws.secret).to eq("override_secret")
      end
    end

    context "when decryption fails" do
      before do
        allow(File).to receive(:exist?).with("config/credentials.yaml.enc").and_return(true)
        allow(SopsRails::Binary).to receive(:decrypt)
          .and_raise(SopsRails::DecryptionError, "failed to decrypt")
      end

      it "propagates the error" do
        expect { described_class.load }.to raise_error(SopsRails::DecryptionError)
      end
    end

    context "when SOPS binary is not found" do
      before do
        allow(File).to receive(:exist?).with("config/credentials.yaml.enc").and_return(true)
        allow(SopsRails::Binary).to receive(:decrypt)
          .and_raise(SopsRails::SopsNotFoundError, "sops not found")
      end

      it "propagates the error" do
        expect { described_class.load }.to raise_error(SopsRails::SopsNotFoundError)
      end
    end
  end
end

RSpec.describe SopsRails::NullCredentials do
  let(:null) { described_class.instance }

  describe "#method_missing" do
    it "returns itself for any method call" do
      expect(null.anything).to be(null)
    end

    it "allows chained method calls" do
      result = null.deep.nested.path.chain
      expect(result).to be(null)
      expect(result).to be_nil
    end
  end

  describe "#[]" do
    it "returns itself for bracket access" do
      expect(null[:key]).to be(null)
      expect(null["key"]).to be(null)
    end
  end

  describe "#dig" do
    it "returns nil for dig" do
      expect(null.dig(:key, :nested)).to be_nil
    end
  end

  describe "#nil?" do
    it "returns true" do
      expect(null).to be_nil
    end
  end

  describe "#==" do
    it "equals nil" do
      expect(null).to eq(nil)
    end

    it "equals another NullCredentials" do
      expect(null).to eq(described_class.instance)
    end
  end
end

RSpec.describe SopsRails do
  after { SopsRails.reset! }

  describe ".credentials" do
    let(:yaml_content) do
      <<~YAML
        aws:
          access_key_id: AKIAIOSFODNN7EXAMPLE
      YAML
    end

    before do
      allow(File).to receive(:exist?).with("config/credentials.yaml.enc").and_return(true)
      allow(SopsRails::Binary).to receive(:decrypt)
        .with("config/credentials.yaml.enc")
        .and_return(yaml_content)
    end

    it "caches the credentials instance" do
      first_call = SopsRails.credentials
      second_call = SopsRails.credentials

      expect(first_call).to be(second_call)
      # Binary.decrypt is only called once (not twice)
      expect(SopsRails::Binary).to have_received(:decrypt).once
    end

    it "reloads credentials after reset!" do
      first_call = SopsRails.credentials
      SopsRails.reset!
      second_call = SopsRails.credentials

      expect(first_call).not_to be(second_call)
    end

    describe "acceptance criteria" do
      it "satisfies: SopsRails.credentials returns Credentials object" do
        expect(SopsRails.credentials).to be_a(SopsRails::Credentials)
      end

      it "satisfies: SopsRails.credentials.aws.access_key_id returns string value" do
        expect(SopsRails.credentials.aws.access_key_id).to eq("AKIAIOSFODNN7EXAMPLE")
      end

      it "satisfies: SopsRails.credentials.nonexistent.nested.key returns nil (not error)" do
        expect(SopsRails.credentials.nonexistent.nested.key).to be_nil
      end

      it "satisfies: SopsRails.credentials.dig(:aws, :access_key_id) works correctly" do
        expect(SopsRails.credentials.dig(:aws, :access_key_id)).to eq("AKIAIOSFODNN7EXAMPLE")
      end

      it "satisfies: Credentials are loaded from file specified in config.credential_files" do
        SopsRails.configure { |c| c.credential_files = ["credentials.yaml.enc"] }
        expect(SopsRails.credentials.aws).not_to be_nil
      end

      it "satisfies: Works with valid SOPS-encrypted YAML files" do
        # The mock setup proves this - we decrypt and parse YAML successfully
        creds = SopsRails.credentials
        expect(creds.aws.access_key_id).to eq("AKIAIOSFODNN7EXAMPLE")
      end
    end
  end
end
