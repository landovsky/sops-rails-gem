# frozen_string_literal: true

require "spec_helper"
require "rake"
require "tmpdir"

# Set up rake environment and load the tasks file only if not already loaded
Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
load File.expand_path("../../../lib/sops_rails/tasks/sops.rake", __dir__) unless defined?(SopsEditTask)

RSpec.describe SopsEditTask do
  around do |example|
    # Save and restore RAILS_ENV for clean test state
    original_env = ENV.fetch("RAILS_ENV", nil)
    example.run
    ENV["RAILS_ENV"] = original_env
  end

  describe ".resolve_file_path" do
    before do
      SopsRails.configure do |config|
        config.encrypted_path = "config"
        config.credential_files = ["credentials.yaml.enc"]
      end
      ENV["RAILS_ENV"] = nil
    end

    context "with explicit file argument" do
      it "returns the file argument" do
        path = described_class.resolve_file_path("config/secrets.yaml.enc")
        expect(path).to eq("config/secrets.yaml.enc")
      end

      it "returns file argument even if RAILS_ENV is set" do
        ENV["RAILS_ENV"] = "production"
        path = described_class.resolve_file_path("config/secrets.yaml.enc")
        expect(path).to eq("config/secrets.yaml.enc")
      end
    end

    context "with RAILS_ENV but no file" do
      it "returns environment-specific credentials path for production" do
        ENV["RAILS_ENV"] = "production"
        path = described_class.resolve_file_path(nil)
        expect(path).to eq("config/credentials.production.yaml.enc")
      end

      it "handles staging environment" do
        ENV["RAILS_ENV"] = "staging"
        path = described_class.resolve_file_path(nil)
        expect(path).to eq("config/credentials.staging.yaml.enc")
      end
    end

    context "with neither file nor RAILS_ENV" do
      it "returns default credentials path" do
        path = described_class.resolve_file_path(nil)
        expect(path).to eq("config/credentials.yaml.enc")
      end
    end

    context "with empty strings" do
      it "treats empty file as nil" do
        ENV["RAILS_ENV"] = "production"
        path = described_class.resolve_file_path("")
        expect(path).to eq("config/credentials.production.yaml.enc")
      end
    end

    context "with custom configuration" do
      before do
        SopsRails.configure do |config|
          config.encrypted_path = "secrets"
          config.credential_files = ["custom.yaml.enc"]
        end
      end

      it "uses custom encrypted_path with RAILS_ENV" do
        ENV["RAILS_ENV"] = "production"
        path = described_class.resolve_file_path(nil)
        expect(path).to eq("secrets/credentials.production.yaml.enc")
      end

      it "uses custom default credential file" do
        path = described_class.resolve_file_path(nil)
        expect(path).to eq("secrets/custom.yaml.enc")
      end
    end
  end

  describe ".ensure_template_exists" do
    let(:file_path) { "config/credentials.yaml.enc" }

    before do
      allow(SopsRails::Binary).to receive(:encrypt_to_file).and_return(true)
    end

    context "when file does not exist" do
      before do
        allow(File).to receive(:exist?).with(file_path).and_return(false)
      end

      it "creates the file with template content" do
        expect(SopsRails::Binary).to receive(:encrypt_to_file).with(
          file_path,
          a_string_including("secret_key_base:")
        )
        described_class.ensure_template_exists(file_path)
      end

      it "returns true" do
        expect(described_class.ensure_template_exists(file_path)).to be true
      end

      it "outputs creation message" do
        expect { described_class.ensure_template_exists(file_path) }
          .to output(/Creating new credentials file/).to_stdout
      end

      it "includes secret_key_base in template" do
        expect(SopsRails::Binary).to receive(:encrypt_to_file) do |_path, content|
          expect(content).to include("secret_key_base:")
          expect(content).to match(/secret_key_base: [a-f0-9]{128}/)
          true
        end
        described_class.ensure_template_exists(file_path)
      end

      it "includes example structure comments in template" do
        expect(SopsRails::Binary).to receive(:encrypt_to_file) do |_path, content|
          expect(content).to include("# aws:")
          expect(content).to include("#   access_key_id:")
          expect(content).to include("# database:")
          true
        end
        described_class.ensure_template_exists(file_path)
      end
    end

    context "when file already exists" do
      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
      end

      it "does not create the file" do
        expect(SopsRails::Binary).not_to receive(:encrypt_to_file)
        described_class.ensure_template_exists(file_path)
      end

      it "returns false" do
        expect(described_class.ensure_template_exists(file_path)).to be false
      end
    end
  end

  describe "acceptance criteria" do
    before do
      SopsRails.configure do |config|
        config.encrypted_path = "config"
        config.credential_files = ["credentials.yaml.enc"]
      end
      ENV["RAILS_ENV"] = nil
    end

    describe "resolving with no arguments returns default path" do
      it "resolves to default credentials file" do
        path = described_class.resolve_file_path(nil)
        expect(path).to eq("config/credentials.yaml.enc")
      end
    end

    describe "resolving with RAILS_ENV=production" do
      it "resolves to environment-specific file" do
        ENV["RAILS_ENV"] = "production"
        path = described_class.resolve_file_path(nil)
        expect(path).to eq("config/credentials.production.yaml.enc")
      end
    end

    describe "resolving with custom file path" do
      it "uses the provided path" do
        path = described_class.resolve_file_path("config/custom.yaml.enc")
        expect(path).to eq("config/custom.yaml.enc")
      end
    end

    describe "file argument takes priority over RAILS_ENV" do
      it "uses explicit file even when RAILS_ENV is set" do
        ENV["RAILS_ENV"] = "production"
        path = described_class.resolve_file_path("config/custom.yaml.enc")
        expect(path).to eq("config/custom.yaml.enc")
      end
    end

    describe "creating new file with template" do
      let(:file_path) { "config/new_credentials.yaml.enc" }

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(false)
        allow(SopsRails::Binary).to receive(:encrypt_to_file).and_return(true)
      end

      it "creates template with secret_key_base mimicking Rails credentials" do
        expect(SopsRails::Binary).to receive(:encrypt_to_file) do |path, content|
          expect(path).to eq(file_path)
          expect(content).to include("secret_key_base:")
          expect(content).to include("MessageVerifiers")
          true
        end
        described_class.ensure_template_exists(file_path)
      end
    end
  end
end

# Integration tests - require real SOPS binary and age keys
RSpec.describe SopsEditTask, "integration tests", :integration do
  include_context "with clean environment"

  let(:temp_dir) { Dir.mktmpdir }
  let(:test_file) { File.join(temp_dir, "credentials.yaml.enc") }

  before do
    skip ".sops.yaml not found - run sops:init first" unless File.exist?(".sops.yaml")
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe ".ensure_template_exists with real encryption" do
    it "creates a valid encrypted SOPS file" do
      # Act: Create template file
      result = described_class.ensure_template_exists(test_file)

      # Assert: File was created
      expect(result).to be true
      expect(File.exist?(test_file)).to be true

      # Assert: File is valid SOPS format
      expect(valid_sops_file?(test_file)).to be true
    end

    it "creates file that can be decrypted" do
      # Act: Create template file
      described_class.ensure_template_exists(test_file)

      # Assert: Can decrypt the file
      expect { SopsRails::Binary.decrypt(test_file) }.not_to raise_error

      # Assert: Decrypted content is not empty
      decrypted_content = SopsRails::Binary.decrypt(test_file)
      expect(decrypted_content).not_to be_empty
    end

    it "creates template with expected YAML structure" do
      # Act: Create template file and decrypt
      described_class.ensure_template_exists(test_file)
      decrypted_content = SopsRails::Binary.decrypt(test_file)

      # Assert: Parse YAML successfully
      parsed = YAML.safe_load(decrypted_content, permitted_classes: [], permitted_symbols: [], aliases: true)
      expect(parsed).to be_a(Hash)

      # Assert: Contains secret_key_base
      expect(parsed).to have_key("secret_key_base")
      expect(parsed["secret_key_base"]).to be_a(String)
      expect(parsed["secret_key_base"]).to match(/^[a-f0-9]{128}$/)
    end

    it "creates template with Rails-like comments" do
      # Act: Create template file and decrypt
      described_class.ensure_template_exists(test_file)
      decrypted_content = SopsRails::Binary.decrypt(test_file)

      # Assert: Contains expected comment structure
      expect(decrypted_content).to include("MessageVerifiers")
      expect(decrypted_content).to include("# aws:")
      expect(decrypted_content).to include("#   access_key_id:")
      expect(decrypted_content).to include("# database:")
      expect(decrypted_content).to include("#   password:")
    end

    it "generates unique secret_key_base each time" do
      # Act: Create two template files
      file1 = File.join(temp_dir, "credentials1.yaml.enc")
      file2 = File.join(temp_dir, "credentials2.yaml.enc")

      described_class.ensure_template_exists(file1)
      described_class.ensure_template_exists(file2)

      # Assert: Decrypt both files
      content1 = SopsRails::Binary.decrypt(file1)
      content2 = SopsRails::Binary.decrypt(file2)

      # Assert: Parse YAML
      parsed1 = YAML.safe_load(content1)
      parsed2 = YAML.safe_load(content2)

      # Assert: secret_key_base values are different
      expect(parsed1["secret_key_base"]).not_to eq(parsed2["secret_key_base"])
    end

    it "returns false when file already exists" do
      # Arrange: Create file first
      described_class.ensure_template_exists(test_file)

      # Act: Try to create again
      result = described_class.ensure_template_exists(test_file)

      # Assert: Returns false (did not create)
      expect(result).to be false
    end

    context "when validating SOPS file format" do
      before do
        described_class.ensure_template_exists(test_file)
      end

      it "contains sops metadata key" do
        content = File.read(test_file)
        parsed = YAML.safe_load(content, permitted_classes: [Time])
        expect(parsed).to have_key("sops")
      end

      it "has valid SOPS metadata structure" do
        content = File.read(test_file)
        parsed = YAML.safe_load(content, permitted_classes: [Time])
        sops_meta = parsed["sops"]

        expect(sops_meta).to have_key("mac")
        expect(sops_meta).to have_key("lastmodified")
        expect(sops_meta).to have_key("version")
      end

      it "passes sops --file-status check" do
        _stdout, stderr, status = Open3.capture3("sops", "--file-status", test_file)
        expect(status.success?).to be(true), "sops --file-status failed: #{stderr}"
      end
    end
  end
end
