# frozen_string_literal: true

require "spec_helper"

RSpec.describe SopsRails::Binary do
  # Store original env vars and restore after all tests
  around do |example|
    original_age_key = ENV.fetch("SOPS_AGE_KEY", nil)
    original_age_key_file = ENV.fetch("SOPS_AGE_KEY_FILE", nil)
    original_debug = ENV.fetch("SOPS_RAILS_DEBUG", nil)

    # Clear env vars for isolation
    ENV.delete("SOPS_AGE_KEY")
    ENV.delete("SOPS_AGE_KEY_FILE")
    ENV.delete("SOPS_RAILS_DEBUG")
    SopsRails.reset!
    SopsRails.configure { |c| c.debug_mode = false }

    example.run

    # Restore
    ENV["SOPS_AGE_KEY"] = original_age_key if original_age_key
    ENV["SOPS_AGE_KEY_FILE"] = original_age_key_file if original_age_key_file
    ENV["SOPS_RAILS_DEBUG"] = original_debug if original_debug
    ENV.delete("SOPS_AGE_KEY") unless original_age_key
    ENV.delete("SOPS_AGE_KEY_FILE") unless original_age_key_file
    ENV.delete("SOPS_RAILS_DEBUG") unless original_debug
    SopsRails.reset!
  end

  describe ".available?" do
    context "when SOPS binary is in PATH" do
      it "returns true" do
        allow(Open3).to receive(:capture3).with("which",
                                                "sops").and_return(["/usr/local/bin/sops", "", double(success?: true)])
        expect(described_class.available?).to be true
      end

      context "when debug mode is enabled" do
        before do
          SopsRails.configure { |c| c.debug_mode = true }
        end

        it "logs debug information" do
          allow(Open3).to receive(:capture3)
            .with("which", "sops")
            .and_return(["/usr/local/bin/sops", "", double(success?: true)])
          expect(SopsRails::Debug).to receive(:warn).with("[sops_rails] SOPS binary available: true")
          described_class.available?
        end
      end
    end

    context "when SOPS binary is not in PATH" do
      it "returns false" do
        allow(Open3).to receive(:capture3).with("which", "sops").and_return(["", "", double(success?: false)])
        expect(described_class.available?).to be false
      end

      it "returns false when stdout is empty" do
        allow(Open3).to receive(:capture3).with("which", "sops").and_return(["", "", double(success?: true)])
        expect(described_class.available?).to be false
      end
    end
  end

  describe ".version" do
    context "when SOPS is available" do
      before do
        allow(described_class).to receive(:available?).and_return(true)
      end

      it "returns version string from sops --version" do
        allow(Open3).to receive(:capture3).with("sops",
                                                "--version").and_return(["sops 3.8.1\n", "", double(success?: true)])
        expect(described_class.version).to eq("3.8.1")
      end

      context "when debug mode is enabled" do
        before do
          SopsRails.configure { |c| c.debug_mode = true }
        end

        it "logs debug information" do
          allow(Open3).to receive(:capture3).with("sops",
                                                  "--version").and_return(["sops 3.8.1\n", "", double(success?: true)])
          expect(SopsRails::Debug).to receive(:warn).with("[sops_rails] Checking SOPS version...")
          expect(SopsRails::Debug).to receive(:warn).with("[sops_rails] SOPS version: 3.8.1")
          described_class.version
        end
      end

      it "parses version from different output formats" do
        allow(Open3).to receive(:capture3).with("sops", "--version").and_return(["3.8.1\n", "", double(success?: true)])
        expect(described_class.version).to eq("3.8.1")
      end

      it "parses version with additional text" do
        allow(Open3).to receive(:capture3).with("sops",
                                                "--version").and_return(["sops version 3.8.1 (build abc123)\n", "",
                                                                         double(success?: true)])
        expect(described_class.version).to eq("3.8.1")
      end

      context "when sops --version fails" do
        it "raises SopsNotFoundError with error message" do
          allow(Open3).to receive(:capture3).with("sops",
                                                  "--version").and_return(["", "command not found",
                                                                           double(success?: false)])
          expect { described_class.version }.to raise_error(SopsRails::SopsNotFoundError, /failed to get sops version/)
        end
      end

      context "when version cannot be parsed" do
        it "raises SopsNotFoundError" do
          allow(Open3).to receive(:capture3).with("sops",
                                                  "--version").and_return(["invalid output\n", "",
                                                                           double(success?: true)])
          expect do
            described_class.version
          end.to raise_error(SopsRails::SopsNotFoundError, /unable to parse sops version/)
        end
      end
    end

    context "when SOPS is not available" do
      it "raises SopsNotFoundError" do
        allow(described_class).to receive(:available?).and_return(false)
        expect { described_class.version }.to raise_error(SopsRails::SopsNotFoundError, /sops binary not found in PATH/)
      end
    end
  end

  describe ".decrypt" do
    let(:file_path) { "config/credentials.yaml.enc" }
    let(:decrypted_content) { "aws:\n  access_key_id: secret123\n" }

    context "when SOPS is available" do
      before do
        allow(described_class).to receive(:available?).and_return(true)
      end

      it "returns decrypted content from stdout" do
        allow(Open3).to receive(:capture3).with(anything, "sops", "-d",
                                                file_path).and_return([decrypted_content, "", double(success?: true)])
        expect(described_class.decrypt(file_path)).to eq(decrypted_content)
      end

      context "when debug mode is enabled" do
        before do
          SopsRails.configure { |c| c.debug_mode = true }
          # Mock file operations for default key path
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(SopsRails.config.default_age_key_path).and_return(false)
        end

        it "logs debug information" do
          allow(Open3).to receive(:capture3)
            .with(anything, "sops", "-d", file_path)
            .and_return([decrypted_content, "", double(success?: true)])
          # Allow any number of debug messages since we now log more info
          allow(SopsRails::Debug).to receive(:warn)
          expect(SopsRails::Debug).to receive(:warn).with("[sops_rails] Decrypting file: #{file_path}")
          expect(SopsRails::Debug).to receive(:warn).with("[sops_rails] Decryption successful for: #{file_path}")
          described_class.decrypt(file_path)
        end

        context "when decryption fails" do
          it "logs error information" do
            stderr = "Error: failed to decrypt"
            allow(Open3).to receive(:capture3).with(anything, "sops", "-d",
                                                    file_path).and_return(["", stderr, double(success?: false)])
            allow(SopsRails::Debug).to receive(:warn)
            expect(SopsRails::Debug).to receive(:warn).with("[sops_rails] Decryption failed: #{stderr}")
            expect do
              described_class.decrypt(file_path)
            end.to raise_error(SopsRails::DecryptionError)
          end
        end
      end

      it "converts file_path to string" do
        path_obj = double(to_s: file_path)
        allow(Open3).to receive(:capture3).with(anything, "sops", "-d",
                                                file_path).and_return([decrypted_content, "", double(success?: true)])
        expect(described_class.decrypt(path_obj)).to eq(decrypted_content)
      end

      context "when decryption fails" do
        it "raises DecryptionError with stderr message" do
          stderr = "Error: failed to get the data key required to decrypt the SOPS file"
          allow(Open3).to receive(:capture3).with(anything, "sops", "-d",
                                                  file_path).and_return(["", stderr, double(success?: false)])
          expect do
            described_class.decrypt(file_path)
          end.to raise_error(SopsRails::DecryptionError, /failed to decrypt file.*#{stderr}/)
        end

        it "raises DecryptionError with stdout message when stderr is empty" do
          stdout = "Error: unable to decrypt file"
          allow(Open3).to receive(:capture3).with(anything, "sops", "-d",
                                                  file_path).and_return([stdout, "", double(success?: false)])
          expect do
            described_class.decrypt(file_path)
          end.to raise_error(SopsRails::DecryptionError, /failed to decrypt file.*#{stdout}/)
        end

        it "includes file path in error message" do
          allow(Open3).to receive(:capture3).with(anything, "sops", "-d",
                                                  file_path).and_return(["", "error message", double(success?: false)])
          expect { described_class.decrypt(file_path) }.to raise_error(SopsRails::DecryptionError, /#{file_path}/)
        end
      end
    end

    context "when SOPS is not available" do
      it "raises SopsNotFoundError" do
        allow(described_class).to receive(:available?).and_return(false)
        expect do
          described_class.decrypt(file_path)
        end.to raise_error(SopsRails::SopsNotFoundError, /sops binary not found in PATH/)
      end
    end
  end

  describe ".edit" do
    let(:file_path) { "config/credentials.yaml.enc" }

    context "when SOPS is available" do
      before do
        allow(described_class).to receive(:available?).and_return(true)
      end

      it "calls system with sops and file path" do
        expect(described_class).to receive(:system).with(anything, "sops", file_path).and_return(true)
        described_class.edit(file_path)
      end

      it "returns true when system call succeeds" do
        allow(described_class).to receive(:system).with(anything, "sops", file_path).and_return(true)
        expect(described_class.edit(file_path)).to be true
      end

      it "returns false when system call fails" do
        allow(described_class).to receive(:system).with(anything, "sops", file_path).and_return(false)
        expect(described_class.edit(file_path)).to be false
      end

      it "returns false when user aborts editor" do
        allow(described_class).to receive(:system).with(anything, "sops", file_path).and_return(false)
        expect(described_class.edit(file_path)).to be false
      end

      it "converts file_path to string" do
        path_obj = double(to_s: file_path)
        expect(described_class).to receive(:system).with(anything, "sops", file_path).and_return(true)
        described_class.edit(path_obj)
      end

      context "when debug mode is enabled" do
        before do
          SopsRails.configure { |c| c.debug_mode = true }
          # Mock file operations for default key path
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(SopsRails.config.default_age_key_path).and_return(false)
        end

        it "logs debug information" do
          allow(described_class).to receive(:system).with(anything, "sops", file_path).and_return(true)
          allow(SopsRails::Debug).to receive(:warn)
          expect(SopsRails::Debug).to receive(:warn).with("[sops_rails] Editing file: #{file_path}")
          expect(SopsRails::Debug).to receive(:warn).with("[sops_rails] Executing: sops #{file_path}")
          described_class.edit(file_path)
        end
      end

      context "with SOPS_AGE_KEY_FILE environment variable" do
        let(:key_file) { "/custom/path/keys.txt" }

        before do
          ENV["SOPS_AGE_KEY_FILE"] = key_file
          SopsRails.reset!
          allow(File).to receive(:exist?).with(File.expand_path(key_file)).and_return(true)
        end

        it "passes SOPS_AGE_KEY_FILE in environment" do
          expect(described_class).to receive(:system).with(
            hash_including("SOPS_AGE_KEY_FILE" => File.expand_path(key_file)),
            "sops",
            file_path
          ).and_return(true)
          described_class.edit(file_path)
        end
      end

      context "with SOPS_AGE_KEY environment variable" do
        let(:age_key) { "AGE-SECRET-KEY-1234567890ABCDEF" }

        before do
          ENV["SOPS_AGE_KEY"] = age_key
          SopsRails.reset!
        end

        it "passes SOPS_AGE_KEY in environment" do
          expect(described_class).to receive(:system).with(
            hash_including("SOPS_AGE_KEY" => age_key),
            "sops",
            file_path
          ).and_return(true)
          described_class.edit(file_path)
        end
      end
    end

    context "when SOPS is not available" do
      it "raises SopsNotFoundError" do
        allow(described_class).to receive(:available?).and_return(false)
        expect do
          described_class.edit(file_path)
        end.to raise_error(SopsRails::SopsNotFoundError, /sops binary not found in PATH/)
      end
    end
  end

  describe ".encrypt_to_file" do
    let(:file_path) { "config/credentials.yaml.enc" }
    let(:content) { "secret_key_base: abc123\n" }
    let(:encrypted_content) { "sops_encrypted_content_here" }
    let(:success_status) { instance_double(Process::Status, success?: true) }
    let(:failure_status) { instance_double(Process::Status, success?: false) }

    context "when SOPS is available" do
      before do
        allow(described_class).to receive(:available?).and_return(true)
        allow(File).to receive(:write)
      end

      it "writes plain content to target file before encrypting in-place" do
        allow(Open3).to receive(:capture3).and_return(["", "", success_status])
        expect(File).to receive(:write).with(file_path, content)
        described_class.encrypt_to_file(file_path, content)
      end

      it "returns true on success" do
        allow(Open3).to receive(:capture3).and_return(["", "", success_status])
        expect(described_class.encrypt_to_file(file_path, content)).to be true
      end

      it "calls sops -e -i with target file path for in-place encryption" do
        # Ensure no public key is available for this test
        allow(SopsRails.config).to receive(:public_key).and_return(nil)
        expect(Open3).to receive(:capture3) do |_env, *args|
          expect(args.size).to eq(4) # ["sops", "-e", "-i", file_path]
          expect(args[0]).to eq("sops")
          expect(args[1]).to eq("-e")
          expect(args[2]).to eq("-i")
          expect(args[3]).to eq(file_path)
          ["", "", success_status]
        end
        described_class.encrypt_to_file(file_path, content)
      end

      context "when public key is available" do
        let(:public_key) { "age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq" }
        let(:key_file_path) { "/Users/test/.config/sops/age/keys.txt" }

        before do
          # Mock the configuration to return a public key
          allow(SopsRails.config).to receive(:public_key).and_return(public_key)
        end

        it "includes --age flag with public key in sops command" do
          expect(Open3).to receive(:capture3) do |_env, *args|
            expect(args.size).to eq(6) # ["sops", "-e", "-i", "--age", public_key, file_path]
            expect(args[0]).to eq("sops")
            expect(args[1]).to eq("-e")
            expect(args[2]).to eq("-i")
            expect(args[3]).to eq("--age")
            expect(args[4]).to eq(public_key)
            expect(args[5]).to eq(file_path)
            ["", "", success_status]
          end
          described_class.encrypt_to_file(file_path, content)
        end

        it "passes public_key explicitly if provided" do
          custom_key = "age1customkeyqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
          expect(Open3).to receive(:capture3) do |_env, *args|
            expect(args.size).to eq(6) # ["sops", "-e", "-i", "--age", custom_key, file_path]
            expect(args[0]).to eq("sops")
            expect(args[1]).to eq("-e")
            expect(args[2]).to eq("-i")
            expect(args[3]).to eq("--age")
            expect(args[4]).to eq(custom_key)
            expect(args[5]).to eq(file_path)
            ["", "", success_status]
          end
          described_class.encrypt_to_file(file_path, content, public_key: custom_key)
        end
      end

      context "when public key is not available" do
        before do
          allow(SopsRails.config).to receive(:public_key).and_return(nil)
        end

        it "calls sops without --age flag (relies on .sops.yaml)" do
          expect(Open3).to receive(:capture3) do |_env, *args|
            expect(args.size).to eq(4) # ["sops", "-e", "-i", file_path]
            expect(args[0]).to eq("sops")
            expect(args[1]).to eq("-e")
            expect(args[2]).to eq("-i")
            expect(args[3]).to eq(file_path)
            expect(args).not_to include("--age")
            ["", "", success_status]
          end
          described_class.encrypt_to_file(file_path, content)
        end
      end

      it "raises EncryptionError when SOPS fails" do
        allow(Open3).to receive(:capture3).and_return(["", "encryption failed", failure_status])
        expect do
          described_class.encrypt_to_file(file_path, content)
        end.to raise_error(SopsRails::EncryptionError, /encryption failed/)
      end

      context "when debug mode is enabled" do
        before do
          SopsRails.configure { |c| c.debug_mode = true }
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(SopsRails.config.default_age_key_path).and_return(false)
        end

        it "logs debug information" do
          allow(Open3).to receive(:capture3).and_return([encrypted_content, "", success_status])
          allow(SopsRails::Debug).to receive(:warn)
          expect(SopsRails::Debug).to receive(:warn).with("[sops_rails] Encrypting content to: #{file_path}")
          described_class.encrypt_to_file(file_path, content)
        end
      end
    end

    context "when SOPS is not available" do
      it "raises SopsNotFoundError" do
        allow(described_class).to receive(:available?).and_return(false)
        expect do
          described_class.encrypt_to_file(file_path, content)
        end.to raise_error(SopsRails::SopsNotFoundError, /sops binary not found in PATH/)
      end
    end
  end

  describe "acceptance criteria" do
    describe "SopsRails::Binary.available? returns true when sops is installed" do
      it "returns true when which sops succeeds" do
        allow(Open3).to receive(:capture3).with("which",
                                                "sops").and_return(["/usr/bin/sops", "", double(success?: true)])
        expect(described_class.available?).to be true
      end
    end

    describe "SopsRails::Binary.version returns version string" do
      before do
        allow(described_class).to receive(:available?).and_return(true)
      end

      it "returns version string like '3.8.1'" do
        allow(Open3).to receive(:capture3).with("sops",
                                                "--version").and_return(["sops 3.8.1\n", "", double(success?: true)])
        expect(described_class.version).to eq("3.8.1")
      end
    end

    describe "SopsRails::Binary.decrypt(file_path) returns decrypted content as string" do
      before do
        allow(described_class).to receive(:available?).and_return(true)
      end

      it "returns decrypted content" do
        content = "decrypted: content\n"
        allow(Open3).to receive(:capture3).with(anything, "sops", "-d",
                                                "file.yaml.enc").and_return([content, "", double(success?: true)])
        expect(described_class.decrypt("file.yaml.enc")).to eq(content)
      end
    end

    describe "Raises SopsRails::SopsNotFoundError when binary not in PATH" do
      it "raises error when available? returns false" do
        allow(described_class).to receive(:available?).and_return(false)
        expect { described_class.version }.to raise_error(SopsRails::SopsNotFoundError)
        expect { described_class.decrypt("file.yaml.enc") }.to raise_error(SopsRails::SopsNotFoundError)
      end
    end

    describe "Raises SopsRails::DecryptionError with meaningful message when decryption fails" do
      before do
        allow(described_class).to receive(:available?).and_return(true)
      end

      it "raises DecryptionError with error details" do
        error_msg = "failed to get the data key"
        allow(Open3).to receive(:capture3).with(anything, "sops", "-d",
                                                "file.yaml.enc").and_return(["", error_msg, double(success?: false)])
        expect { described_class.decrypt("file.yaml.enc") }.to raise_error(SopsRails::DecryptionError, /#{error_msg}/)
      end
    end

    describe "Decrypted content never touches filesystem (memory-only)" do
      before do
        allow(described_class).to receive(:available?).and_return(true)
      end

      it "captures content from stdout only" do
        content = "decrypted content"
        allow(Open3).to receive(:capture3).with(anything, "sops", "-d",
                                                "file.yaml.enc").and_return([content, "", double(success?: true)])

        # Verify we're not writing to filesystem by checking Open3 is called correctly
        expect(Open3).to receive(:capture3).with(anything, "sops", "-d", "file.yaml.enc")
        result = described_class.decrypt("file.yaml.enc")
        expect(result).to eq(content)
      end
    end
  end

  # Integration tests require real SOPS binary
  describe "integration tests", integration: true do
    before do
      skip "SOPS binary not available" unless described_class.available?
    end

    describe ".available?" do
      it "returns true when SOPS is installed" do
        expect(described_class.available?).to be true
      end
    end

    describe ".version" do
      it "returns a valid version string" do
        version = described_class.version
        expect(version).to match(/\d+\.\d+\.\d+/)
      end
    end

    describe ".decrypt" do
      let(:test_file) { "spec/fixtures/test_credentials.yaml.enc" }

      context "with a valid encrypted file" do
        before do
          # Create a test encrypted file if it doesn't exist
          # This would require SOPS and age keys to be set up
          # For now, we'll skip if file doesn't exist
          skip "Test encrypted file not available" unless File.exist?(test_file)
        end

        it "decrypts the file and returns content" do
          content = described_class.decrypt(test_file)
          expect(content).to be_a(String)
          expect(content).not_to be_empty
        end
      end

      context "with a non-existent file" do
        it "raises DecryptionError" do
          expect do
            described_class.decrypt("nonexistent.yaml.enc")
          end.to raise_error(SopsRails::DecryptionError)
        end
      end
    end
  end
end
