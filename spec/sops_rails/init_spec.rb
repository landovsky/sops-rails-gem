# frozen_string_literal: true

require "spec_helper"
require "sops_rails/init"
require "tmpdir"
require "fileutils"

RSpec.describe SopsRails::Init do
  let(:tmpdir) { Dir.mktmpdir }

  around do |example|
    Dir.chdir(tmpdir) do
      example.run
    end
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  before do
    allow(described_class).to receive(:puts) # Suppress output in tests
    allow(described_class).to receive(:print) # Suppress prompts in tests
  end

  describe ".age_available?" do
    context "when age binary is in PATH" do
      it "returns true" do
        allow(Open3).to receive(:capture3).with("which",
                                                "age").and_return(["/usr/local/bin/age", "", double(success?: true)])
        expect(described_class.age_available?).to be true
      end
    end

    context "when age binary is not in PATH" do
      it "returns false" do
        allow(Open3).to receive(:capture3).with("which", "age").and_return(["", "", double(success?: false)])
        expect(described_class.age_available?).to be false
      end

      it "returns false when stdout is empty" do
        allow(Open3).to receive(:capture3).with("which", "age").and_return(["", "", double(success?: true)])
        expect(described_class.age_available?).to be false
      end
    end
  end

  describe ".check_prerequisites" do
    context "when both sops and age are available" do
      before do
        allow(SopsRails::Binary).to receive(:available?).and_return(true)
        allow(SopsRails::Binary).to receive(:version).and_return("3.8.1")
        allow(described_class).to receive(:age_available?).and_return(true)
      end

      it "does not raise an error" do
        expect { described_class.check_prerequisites }.not_to raise_error
      end
    end

    context "when sops is not available" do
      before do
        allow(SopsRails::Binary).to receive(:available?).and_return(false)
      end

      it "raises SopsNotFoundError" do
        expect { described_class.check_prerequisites }.to raise_error(SopsRails::SopsNotFoundError)
      end
    end

    context "when age is not available" do
      before do
        allow(SopsRails::Binary).to receive(:available?).and_return(true)
        allow(SopsRails::Binary).to receive(:version).and_return("3.8.1")
        allow(described_class).to receive(:age_available?).and_return(false)
      end

      it "raises AgeNotFoundError" do
        expect { described_class.check_prerequisites }.to raise_error(SopsRails::AgeNotFoundError)
      end
    end
  end

  describe ".extract_public_key" do
    let(:keys_content) do
      <<~KEYS
        # created: 2024-01-01T00:00:00Z
        # public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
        AGE-SECRET-KEY-1...
      KEYS
    end

    let(:keys_path) { File.join(tmpdir, "keys.txt") }

    before do
      File.write(keys_path, keys_content)
    end

    it "extracts the public key from the keys file" do
      public_key = described_class.extract_public_key(keys_path)
      expect(public_key).to eq("age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p")
    end

    context "when public key cannot be extracted" do
      let(:keys_content) { "invalid content" }

      it "raises an Error" do
        expect { described_class.extract_public_key(keys_path) }.to raise_error(SopsRails::Error)
      end
    end
  end

  describe ".ensure_age_key" do
    let(:age_keys_path) { SopsRails::Init::AGE_KEYS_PATH }
    let(:keys_dir) { File.dirname(age_keys_path) }
    let(:public_key) { "age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p" }
    let(:keys_content) do
      <<~KEYS
        # created: 2024-01-01T00:00:00Z
        # public key: #{public_key}
        AGE-SECRET-KEY-1...
      KEYS
    end

    context "when age key already exists" do
      before do
        # Mock File.exist? to return true for the keys path
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(age_keys_path).and_return(true)
        allow(File).to receive(:read).with(age_keys_path).and_return(keys_content)
      end

      it "returns the existing public key" do
        result = described_class.ensure_age_key(non_interactive: true)
        expect(result).to eq(public_key)
      end

      it "does not generate a new key" do
        expect(Open3).not_to receive(:capture3).with("age-keygen", anything, anything)
        described_class.ensure_age_key(non_interactive: true)
      end
    end

    context "when age key does not exist" do
      before do
        allow(described_class).to receive(:age_available?).and_return(true)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(age_keys_path).and_return(false)
        allow(FileUtils).to receive(:mkdir_p)
      end

      context "when age-keygen succeeds" do
        let(:keygen_output) do
          <<~OUTPUT
            # created: 2024-01-01T00:00:00Z
            # public key: #{public_key}
            AGE-SECRET-KEY-1...
          OUTPUT
        end

        before do
          allow(Open3).to receive(:capture3).with("age-keygen", "-o",
                                                  age_keys_path).and_return([keygen_output, "", double(success?: true)])
          allow(File).to receive(:read).with(age_keys_path).and_return(keygen_output)
          allow(described_class).to receive(:extract_public_key).and_return(public_key)
        end

        it "generates a new key" do
          expect(Open3).to receive(:capture3).with("age-keygen", "-o", age_keys_path)
          described_class.ensure_age_key(non_interactive: true)
        end

        it "creates the keys directory" do
          expect(FileUtils).to receive(:mkdir_p).with(keys_dir)
          described_class.ensure_age_key(non_interactive: true)
        end

        it "returns the generated public key" do
          result = described_class.ensure_age_key(non_interactive: true)
          expect(result).to eq(public_key)
        end
      end

      context "when age-keygen fails" do
        before do
          allow(Open3).to receive(:capture3).with("age-keygen", "-o",
                                                  age_keys_path).and_return(["", "error message",
                                                                             double(success?: false)])
        end

        it "raises AgeNotFoundError" do
          expect { described_class.ensure_age_key(non_interactive: true) }.to raise_error(SopsRails::AgeNotFoundError)
        end
      end
    end
  end

  describe ".create_sops_config" do
    let(:public_key) { "age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p" }
    let(:sops_yaml_path) { ".sops.yaml" }

    context "when .sops.yaml does not exist" do
      it "creates .sops.yaml with correct structure" do
        described_class.create_sops_config(public_key, non_interactive: true)

        expect(File.exist?(sops_yaml_path)).to be true
        config = YAML.load_file(sops_yaml_path)
        expect(config["creation_rules"]).to be_an(Array)
        expect(config["creation_rules"].length).to eq(3)

        # Check credentials rule
        credentials_rule = config["creation_rules"][0]
        expect(credentials_rule["path_regex"]).to eq("config/credentials(\\..*)?\\.yaml\\.enc$")
        expect(credentials_rule["age"]).to eq([public_key])

        # Check env files rule
        env_rule = config["creation_rules"][1]
        expect(env_rule["path_regex"]).to eq("\\.env(\\..*)?\\.enc$")
        expect(env_rule["age"]).to eq([public_key])

        # Check catch-all rule
        catch_all_rule = config["creation_rules"][2]
        expect(catch_all_rule["path_regex"]).to eq(".*")
        expect(catch_all_rule["age"]).to eq("")
      end
    end

    context "when .sops.yaml already exists" do
      before do
        File.write(sops_yaml_path, "existing: content\n")
      end

      context "in non-interactive mode" do
        it "overwrites the file" do
          described_class.create_sops_config(public_key, non_interactive: true)

          config = YAML.load_file(sops_yaml_path)
          expect(config["creation_rules"]).to be_an(Array)
        end
      end

      context "in interactive mode" do
        it "prompts for confirmation" do
          allow($stdin).to receive(:gets).and_return("n\n")
          described_class.create_sops_config(public_key, non_interactive: false)

          expect(File.read(sops_yaml_path)).to eq("existing: content\n")
        end

        it "overwrites when user confirms" do
          allow($stdin).to receive(:gets).and_return("y\n")
          described_class.create_sops_config(public_key, non_interactive: false)

          config = YAML.load_file(sops_yaml_path)
          expect(config["creation_rules"]).to be_an(Array)
        end
      end
    end
  end

  describe ".update_gitignore" do
    let(:gitignore_path) { ".gitignore" }

    context "when .gitignore does not exist" do
      it "creates .gitignore with sops-rails entries" do
        described_class.update_gitignore(non_interactive: true)

        content = File.read(gitignore_path)
        expect(content).to include("# sops-rails")
        expect(content).to include(".env*.local")
        expect(content).to include("*.decrypted.*")
        expect(content).to include("tmp/secrets/")
      end
    end

    context "when .gitignore exists" do
      before do
        File.write(gitignore_path, "existing_entry\n")
      end

      it "appends sops-rails entries" do
        described_class.update_gitignore(non_interactive: true)

        content = File.read(gitignore_path)
        expect(content).to include("existing_entry")
        expect(content).to include("# sops-rails")
        expect(content).to include(".env*.local")
      end

      context "when entries already exist" do
        before do
          File.write(gitignore_path, "existing_entry\n.env*.local\n")
        end

        it "does not duplicate entries" do
          described_class.update_gitignore(non_interactive: true)

          content = File.read(gitignore_path)
          expect(content.scan(".env*.local").length).to eq(1)
        end
      end
    end
  end

  describe ".create_initial_credentials" do
    let(:credentials_path) { "config/credentials.yaml.enc" }
    let(:credentials_dir) { "config" }

    before do
      allow(SopsRails::Binary).to receive(:available?).and_return(true)
      allow(Open3).to receive(:capture3).and_return(["", "", double(success?: true)])
    end

    context "when credentials file does not exist" do
      it "creates the config directory" do
        described_class.create_initial_credentials(non_interactive: true)
        expect(File.directory?(credentials_dir)).to be true
      end

      it "encrypts the template using SOPS" do
        expect(Open3).to receive(:capture3) do |*args|
          expect(args[0]).to eq("sops")
          expect(args[1]).to eq("-e")
          expect(args[2]).to eq("-i")
          expect(args[3]).to end_with(".tmp")
          ["", "", double(success?: true)]
        end

        described_class.create_initial_credentials(non_interactive: true)
      end

      it "creates the encrypted credentials file" do
        # Mock file operations
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:write)
        allow(FileUtils).to receive(:mv)
        allow(FileUtils).to receive(:rm_f)

        described_class.create_initial_credentials(non_interactive: true)

        expect(FileUtils).to have_received(:mv).with(anything, credentials_path)
      end
    end

    context "when credentials file already exists" do
      before do
        FileUtils.mkdir_p(credentials_dir)
        File.write(credentials_path, "encrypted content")
      end

      context "in non-interactive mode" do
        it "overwrites the file" do
          allow(FileUtils).to receive(:mkdir_p)
          allow(File).to receive(:write)
          allow(FileUtils).to receive(:mv)
          allow(FileUtils).to receive(:rm_f)

          described_class.create_initial_credentials(non_interactive: true)

          expect(FileUtils).to have_received(:mv)
        end
      end

      context "in interactive mode" do
        it "prompts for confirmation" do
          allow($stdin).to receive(:gets).and_return("n\n")
          described_class.create_initial_credentials(non_interactive: false)

          expect(File.read(credentials_path)).to eq("encrypted content")
        end

        it "overwrites when user confirms" do
          allow($stdin).to receive(:gets).and_return("y\n")
          allow(FileUtils).to receive(:mkdir_p)
          allow(File).to receive(:write)
          allow(FileUtils).to receive(:mv)
          allow(FileUtils).to receive(:rm_f)

          described_class.create_initial_credentials(non_interactive: false)

          expect(FileUtils).to have_received(:mv)
        end
      end
    end

    context "when encryption fails" do
      before do
        allow(FileUtils).to receive(:mkdir_p)
        allow(File).to receive(:write)
        allow(Open3).to receive(:capture3).and_return(["", "encryption failed", double(success?: false)])
        allow(FileUtils).to receive(:rm_f)
      end

      it "raises EncryptionError" do
        expect { described_class.create_initial_credentials(non_interactive: true) }.to raise_error(SopsRails::EncryptionError)
      end

      it "cleans up temporary file" do
        expect(FileUtils).to receive(:rm_f).with(anything)
        begin
          described_class.create_initial_credentials(non_interactive: true)
        rescue SopsRails::EncryptionError
          # Expected
        end
      end
    end

    context "when public_key is provided" do
      let(:public_key) { "age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p" }

      it "passes the age key explicitly to SOPS to avoid .sops.yaml pattern matching issues" do
        expect(Open3).to receive(:capture3) do |*args|
          expect(args).to include("--age")
          expect(args).to include(public_key)
          ["", "", double(success?: true)]
        end

        described_class.create_initial_credentials(non_interactive: true, public_key: public_key)
      end
    end
  end

  describe ".run" do
    let(:public_key) { "age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p" }

    before do
      allow(described_class).to receive(:check_prerequisites)
      allow(described_class).to receive(:ensure_age_key).and_return(public_key)
      allow(described_class).to receive(:create_sops_config)
      allow(described_class).to receive(:update_gitignore)
      allow(described_class).to receive(:create_initial_credentials)
    end

    it "runs all initialization steps in order" do
      expect(described_class).to receive(:check_prerequisites).ordered
      expect(described_class).to receive(:ensure_age_key).with(non_interactive: false).ordered
      expect(described_class).to receive(:create_sops_config).with(public_key, non_interactive: false).ordered
      expect(described_class).to receive(:update_gitignore).with(non_interactive: false).ordered
      expect(described_class).to receive(:create_initial_credentials).with(non_interactive: false,
                                                                           public_key: public_key).ordered

      described_class.run(non_interactive: false)
    end

    it "passes non_interactive flag and public_key to all methods" do
      described_class.run(non_interactive: true)

      expect(described_class).to have_received(:ensure_age_key).with(non_interactive: true)
      expect(described_class).to have_received(:create_sops_config).with(public_key, non_interactive: true)
      expect(described_class).to have_received(:update_gitignore).with(non_interactive: true)
      expect(described_class).to have_received(:create_initial_credentials).with(non_interactive: true,
                                                                                 public_key: public_key)
    end
  end

  # Integration tests require real SOPS and age binaries with valid keys
  # These tests are skipped by default - run with: RUN_INTEGRATION=1 bundle exec rspec
  describe "integration tests", :integration do
    let(:age_keys_path) { SopsRails::Init::AGE_KEYS_PATH }

    before do
      skip "Integration tests skipped (set RUN_INTEGRATION=1 to run)" unless ENV["RUN_INTEGRATION"] == "1"
      skip "SOPS binary not available" unless SopsRails::Binary.available?
      skip "age binary not available" unless described_class.age_available?
      skip "age key not found at #{age_keys_path}" unless File.exist?(age_keys_path)
    end

    describe ".create_sops_config" do
      let(:public_key) { described_class.extract_public_key(age_keys_path) }

      it "creates valid .sops.yaml that SOPS can use" do
        described_class.create_sops_config(public_key, non_interactive: true)

        expect(File.exist?(".sops.yaml")).to be true

        # Create a test file that matches the credentials pattern
        FileUtils.mkdir_p("config")
        test_file = "config/credentials.test.yaml.enc"
        File.write(test_file, "test: value\n")

        _, stderr, status = Open3.capture3("sops", "-e", "-i", test_file)
        expect(status.success?).to be(true), "SOPS encryption failed: #{stderr}"

        FileUtils.rm_f(test_file)
      end
    end

    describe ".create_initial_credentials" do
      let(:public_key) { described_class.extract_public_key(age_keys_path) }

      before do
        described_class.create_sops_config(public_key, non_interactive: true)
      end

      it "creates an encrypted file that can be decrypted" do
        described_class.create_initial_credentials(non_interactive: true, public_key: public_key)

        expect(File.exist?("config/credentials.yaml.enc")).to be true

        decrypted = SopsRails::Binary.decrypt("config/credentials.yaml.enc")
        expect(decrypted).to include("aws:")
        expect(decrypted).to include("database:")
      end
    end

    describe ".run" do
      it "completes full initialization using existing key" do
        expect { described_class.run(non_interactive: true) }.not_to raise_error

        expect(File.exist?(".sops.yaml")).to be true
        expect(File.exist?(".gitignore")).to be true
        expect(File.exist?("config/credentials.yaml.enc")).to be true

        # Verify credentials file is decryptable
        expect { SopsRails::Binary.decrypt("config/credentials.yaml.enc") }.not_to raise_error
      end
    end
  end
end
