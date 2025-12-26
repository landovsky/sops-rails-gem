# frozen_string_literal: true

require "spec_helper"

RSpec.describe SopsRails::Debug do
  # Store original env vars and restore after all tests
  around do |example|
    original_debug = ENV.fetch("SOPS_RAILS_DEBUG", nil)
    original_age_key = ENV.fetch("SOPS_AGE_KEY", nil)
    original_age_key_file = ENV.fetch("SOPS_AGE_KEY_FILE", nil)

    # Clear all env vars for isolation
    ENV.delete("SOPS_RAILS_DEBUG")
    ENV.delete("SOPS_AGE_KEY")
    ENV.delete("SOPS_AGE_KEY_FILE")
    SopsRails.reset!

    example.run

    # Restore original values
    ENV["SOPS_RAILS_DEBUG"] = original_debug if original_debug
    ENV["SOPS_AGE_KEY"] = original_age_key if original_age_key
    ENV["SOPS_AGE_KEY_FILE"] = original_age_key_file if original_age_key_file
    ENV.delete("SOPS_RAILS_DEBUG") unless original_debug
    ENV.delete("SOPS_AGE_KEY") unless original_age_key
    ENV.delete("SOPS_AGE_KEY_FILE") unless original_age_key_file
    SopsRails.reset!
  end

  # Helper to get the OS-specific default path
  def default_age_key_path
    SopsRails.config.default_age_key_path
  end

  describe ".debug_mode?" do
    context "when debug mode is disabled" do
      it "returns false" do
        expect(described_class.debug_mode?).to be false
      end
    end

    context "when debug mode is enabled via configuration" do
      it "returns true" do
        SopsRails.configure { |c| c.debug_mode = true }
        expect(described_class.debug_mode?).to be true
      end
    end

    context "when debug mode is enabled via environment variable" do
      it "returns true" do
        ENV["SOPS_RAILS_DEBUG"] = "1"
        SopsRails.reset!
        expect(described_class.debug_mode?).to be true
      end
    end
  end

  describe ".log" do
    context "when debug mode is disabled" do
      it "does not output anything" do
        expect($stderr).not_to receive(:puts)
        described_class.log("test message")
      end
    end

    context "when debug mode is enabled" do
      before do
        SopsRails.configure { |c| c.debug_mode = true }
      end

      it "outputs to stderr with prefix" do
        expect(SopsRails::Debug).to receive(:warn).with("[sops_rails] test message")
        described_class.log("test message")
      end

      it "formats messages correctly" do
        expect(SopsRails::Debug).to receive(:warn).with("[sops_rails] Loading file: config/credentials.yaml.enc")
        described_class.log("Loading file: config/credentials.yaml.enc")
      end
    end
  end

  describe ".log_key_info" do
    context "when debug mode is disabled" do
      before do
        # Ensure debug mode is off
        SopsRails.configure { |c| c.debug_mode = false }
      end

      it "does not output anything" do
        expect(described_class).not_to receive(:warn)
        described_class.log_key_info
      end
    end

    context "when debug mode is enabled" do
      before do
        SopsRails.configure { |c| c.debug_mode = true }
        # Mock File.exist? to return false for default location
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(default_age_key_path).and_return(false)
      end

      context "when SOPS_AGE_KEY is set" do
        before do
          ENV["SOPS_AGE_KEY"] = "AGE-SECRET-KEY-1ABC123..."
          SopsRails.reset!
          SopsRails.configure { |c| c.debug_mode = true }
        end

        it "logs SOPS_AGE_KEY as key source" do
          expect(described_class).to receive(:warn).with("[sops_rails] Key source: SOPS_AGE_KEY (environment variable set)")
          expect(described_class).to receive(:warn).with("[sops_rails] Resolved key file: (none)")
          described_class.log_key_info
        end
      end

      context "when SOPS_AGE_KEY_FILE is set" do
        before do
          ENV["SOPS_AGE_KEY_FILE"] = "/path/to/key.txt"
          SopsRails.reset!
          SopsRails.configure { |c| c.debug_mode = true }
        end

        let(:expanded_path) { File.expand_path("/path/to/key.txt") }

        context "when key file exists and is readable" do
          before do
            allow(File).to receive(:exist?).with(expanded_path).and_return(true)
            allow(File).to receive(:readable?).and_call_original
            allow(File).to receive(:readable?).with(expanded_path).and_return(true)
            allow(File).to receive(:foreach).with(expanded_path).and_yield("# public key: age1testkey123")
          end

          it "logs SOPS_AGE_KEY_FILE as key source with file status and public key" do
            expect(described_class).to receive(:warn).with("[sops_rails] Key source: SOPS_AGE_KEY_FILE").ordered
            expect(described_class).to receive(:warn).with("[sops_rails] Key file: #{expanded_path} " \
                                                           "(exists: true, readable: true)").ordered
            expect(described_class).to receive(:warn).with("[sops_rails] Resolved key file: #{expanded_path}").ordered
            expect(described_class).to receive(:warn).with("[sops_rails] Public key: age1testkey123").ordered
            described_class.log_key_info
          end
        end

        context "when key file does not exist" do
          before do
            allow(File).to receive(:exist?).with(expanded_path).and_return(false)
          end

          it "logs SOPS_AGE_KEY_FILE as key source with non-existent status" do
            expect(described_class).to receive(:warn).with("[sops_rails] Key source: SOPS_AGE_KEY_FILE").ordered
            expect(described_class).to receive(:warn).with("[sops_rails] Key file: #{expanded_path} " \
                                                           "(exists: false, readable: false)").ordered
            expect(described_class).to receive(:warn).with("[sops_rails] Resolved key file: (none)").ordered
            described_class.log_key_info
          end
        end
      end

      context "when SOPS_AGE_KEY_FILE is set to empty string" do
        before do
          ENV["SOPS_AGE_KEY_FILE"] = ""
          SopsRails.reset!
          SopsRails.configure { |c| c.debug_mode = true }
          allow(File).to receive(:exist?).with(default_age_key_path).and_return(false)
        end

        it "treats empty string as unset and checks default location" do
          expect(described_class).to receive(:warn).with("[sops_rails] Key source: none (SOPS will use .sops.yaml rules)")
          expect(described_class).to receive(:warn).with("[sops_rails] Resolved key file: (none)")
          described_class.log_key_info
        end
      end

      context "when default key location exists" do
        before do
          allow(File).to receive(:exist?).with(default_age_key_path).and_return(true)
          allow(File).to receive(:readable?).and_call_original
          allow(File).to receive(:readable?).with(default_age_key_path).and_return(true)
          allow(File).to receive(:foreach).with(default_age_key_path).and_yield("# public key: age1defaultkey456")
        end

        it "logs default_location as key source with file status" do
          expect(described_class).to receive(:warn).with("[sops_rails] Key source: default_location").ordered
          expect(described_class).to receive(:warn).with("[sops_rails] Key file: #{default_age_key_path} " \
                                                         "(exists: true, readable: true)").ordered
          expect(described_class).to receive(:warn).with("[sops_rails] Resolved key file: #{default_age_key_path}").ordered
          expect(described_class).to receive(:warn).with("[sops_rails] Public key: age1defaultkey456").ordered
          described_class.log_key_info
        end
      end

      context "when no key source is found" do
        before do
          allow(File).to receive(:exist?).with(default_age_key_path).and_return(false)
        end

        it "logs none as key source" do
          expect(described_class).to receive(:warn).with("[sops_rails] Key source: none (SOPS will use .sops.yaml rules)")
          expect(described_class).to receive(:warn).with("[sops_rails] Resolved key file: (none)")
          described_class.log_key_info
        end
      end
    end
  end

  describe ".info" do
    let(:config) { SopsRails.config }

    before do
      allow(SopsRails::Binary).to receive(:available?).and_return(true)
      allow(SopsRails::Binary).to receive(:version).and_return("3.8.1")
      allow(Open3).to receive(:capture3).with("which", "age").and_return(["/usr/bin/age", "", double(success?: true)])
      # Default: no key file exists
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(default_age_key_path).and_return(false)
    end

    it "returns a hash with debug information" do
      info = described_class.info
      expect(info).to be_a(Hash)
      expect(info).to have_key(:key_source)
      expect(info).to have_key(:key_file)
      expect(info).to have_key(:key_file_exists)
      expect(info).to have_key(:resolved_key_file)
      expect(info).to have_key(:public_key)
      expect(info).to have_key(:sops_version)
      expect(info).to have_key(:age_available)
      expect(info).to have_key(:config)
      expect(info).to have_key(:credential_files)
    end

    it "includes configuration information" do
      info = described_class.info
      expect(info[:config]).to be_a(Hash)
      expect(info[:config][:encrypted_path]).to eq("config")
      expect(info[:config][:credential_files]).to eq(["credentials.yaml.enc"])
      expect(info[:config][:debug_mode]).to be false
    end

    it "includes credential files information" do
      info = described_class.info
      expect(info[:credential_files]).to be_an(Array)
      expect(info[:credential_files].first).to have_key(:pattern)
      expect(info[:credential_files].first).to have_key(:full_path)
      expect(info[:credential_files].first).to have_key(:exists)
      expect(info[:credential_files].first).to have_key(:readable)
    end

    context "when SOPS_AGE_KEY is set" do
      before do
        ENV["SOPS_AGE_KEY"] = "AGE-SECRET-KEY-1ABC123..."
        SopsRails.reset!
      end

      it "detects SOPS_AGE_KEY as key source" do
        info = described_class.info
        expect(info[:key_source]).to eq("SOPS_AGE_KEY")
        expect(info[:key_file]).to be_nil
        expect(info[:key_file_exists]).to be_nil
        expect(info[:resolved_key_file]).to be_nil
      end
    end

    context "when SOPS_AGE_KEY_FILE is set" do
      let(:expanded_path) { File.expand_path("/path/to/key.txt") }

      before do
        ENV["SOPS_AGE_KEY_FILE"] = "/path/to/key.txt"
        SopsRails.reset!
      end

      it "detects SOPS_AGE_KEY_FILE as key source" do
        info = described_class.info
        expect(info[:key_source]).to eq("SOPS_AGE_KEY_FILE")
        expect(info[:key_file]).to eq(expanded_path)
      end

      context "when key file exists" do
        before do
          allow(File).to receive(:exist?).with(expanded_path).and_return(true)
          allow(File).to receive(:readable?).and_call_original
          allow(File).to receive(:readable?).with(expanded_path).and_return(true)
          allow(File).to receive(:foreach).with(expanded_path).and_yield("# public key: age1testpubkey")
        end

        it "reports key file exists and includes resolved path and public key" do
          info = described_class.info
          expect(info[:key_file_exists]).to be true
          expect(info[:resolved_key_file]).to eq(expanded_path)
          expect(info[:public_key]).to eq("age1testpubkey")
        end
      end

      context "when key file does not exist" do
        before do
          allow(File).to receive(:exist?).with(expanded_path).and_return(false)
        end

        it "reports key file does not exist" do
          info = described_class.info
          expect(info[:key_file_exists]).to be false
          expect(info[:resolved_key_file]).to be_nil
        end
      end
    end

    context "when SOPS_AGE_KEY_FILE is set to empty string" do
      before do
        ENV["SOPS_AGE_KEY_FILE"] = ""
        SopsRails.reset!
        allow(File).to receive(:exist?).with(default_age_key_path).and_return(false)
      end

      it "treats empty string as unset and falls back to default location check" do
        info = described_class.info
        expect(info[:key_source]).to eq("none")
        expect(info[:key_file]).to be_nil
        expect(info[:key_file_exists]).to be_nil
        expect(info[:resolved_key_file]).to be_nil
      end
    end

    context "when default key location exists" do
      before do
        allow(File).to receive(:exist?).with(default_age_key_path).and_return(true)
        allow(File).to receive(:readable?).and_call_original
        allow(File).to receive(:readable?).with(default_age_key_path).and_return(true)
        allow(File).to receive(:foreach).with(default_age_key_path).and_yield("# public key: age1defaultpub")
      end

      it "detects default location as key source" do
        info = described_class.info
        expect(info[:key_source]).to eq("default_location")
        expect(info[:key_file]).to eq(default_age_key_path)
        expect(info[:key_file_exists]).to be true
        expect(info[:resolved_key_file]).to eq(default_age_key_path)
        expect(info[:public_key]).to eq("age1defaultpub")
      end
    end

    context "when no key source is found" do
      before do
        allow(File).to receive(:exist?).with(default_age_key_path).and_return(false)
      end

      it "reports none as key source" do
        info = described_class.info
        expect(info[:key_source]).to eq("none")
        expect(info[:key_file]).to be_nil
        expect(info[:key_file_exists]).to be_nil
        expect(info[:resolved_key_file]).to be_nil
        expect(info[:public_key]).to be_nil
      end
    end

    context "when SOPS is not available" do
      before do
        allow(SopsRails::Binary).to receive(:available?).and_return(false)
      end

      it "reports nil for SOPS version" do
        info = described_class.info
        expect(info[:sops_version]).to be_nil
      end
    end

    context "when age is not available" do
      before do
        allow(Open3).to receive(:capture3).with("which", "age").and_return(["", "", double(success?: false)])
      end

      it "reports age as not available" do
        info = described_class.info
        expect(info[:age_available]).to be false
      end
    end
  end
end
