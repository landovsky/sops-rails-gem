# frozen_string_literal: true

require "spec_helper"

RSpec.describe SopsRails::Debug do
  before do
    SopsRails.reset!
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
      around do |example|
        original = ENV.fetch("SOPS_RAILS_DEBUG", nil)
        ENV["SOPS_RAILS_DEBUG"] = "1"
        SopsRails.reset!
        example.run
        ENV["SOPS_RAILS_DEBUG"] = original
        SopsRails.reset!
      end

      it "returns true" do
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

  describe ".info" do
    let(:config) { SopsRails.config }

    before do
      allow(SopsRails::Binary).to receive(:available?).and_return(true)
      allow(SopsRails::Binary).to receive(:version).and_return("3.8.1")
      allow(Open3).to receive(:capture3).with("which", "age").and_return(["/usr/bin/age", "", double(success?: true)])
    end

    it "returns a hash with debug information" do
      info = described_class.info
      expect(info).to be_a(Hash)
      expect(info).to have_key(:key_source)
      expect(info).to have_key(:key_file)
      expect(info).to have_key(:key_file_exists)
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
      around do |example|
        original = ENV.fetch("SOPS_AGE_KEY", nil)
        ENV["SOPS_AGE_KEY"] = "AGE-SECRET-KEY-1ABC123..."
        SopsRails.reset!
        example.run
        ENV["SOPS_AGE_KEY"] = original
        SopsRails.reset!
      end

      it "detects SOPS_AGE_KEY as key source" do
        info = described_class.info
        expect(info[:key_source]).to eq("SOPS_AGE_KEY")
        expect(info[:key_file]).to be_nil
        expect(info[:key_file_exists]).to be_nil
      end
    end

    context "when SOPS_AGE_KEY_FILE is set" do
      around do |example|
        original = ENV.fetch("SOPS_AGE_KEY_FILE", nil)
        ENV["SOPS_AGE_KEY_FILE"] = "/path/to/key.txt"
        SopsRails.reset!
        example.run
        ENV["SOPS_AGE_KEY_FILE"] = original
        SopsRails.reset!
      end

      it "detects SOPS_AGE_KEY_FILE as key source" do
        info = described_class.info
        expect(info[:key_source]).to eq("SOPS_AGE_KEY_FILE")
        expect(info[:key_file]).to eq(File.expand_path("/path/to/key.txt"))
      end

      context "when key file exists" do
        before do
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:readable?).and_call_original
          allow(File).to receive(:exist?).with(File.expand_path("/path/to/key.txt")).and_return(true)
          allow(File).to receive(:readable?).with(File.expand_path("/path/to/key.txt")).and_return(true)
        end

        it "reports key file exists" do
          info = described_class.info
          expect(info[:key_file_exists]).to be true
        end
      end

      context "when key file does not exist" do
        before do
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(File.expand_path("/path/to/key.txt")).and_return(false)
        end

        it "reports key file does not exist" do
          info = described_class.info
          expect(info[:key_file_exists]).to be false
        end
      end
    end

    context "when default key location exists" do
      let(:default_path) { File.expand_path("~/.config/sops/age/keys.txt") }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:readable?).and_call_original
        allow(File).to receive(:exist?).with(default_path).and_return(true)
        allow(File).to receive(:readable?).with(default_path).and_return(true)
      end

      it "detects default location as key source" do
        info = described_class.info
        expect(info[:key_source]).to eq("default_location")
        expect(info[:key_file]).to eq(default_path)
        expect(info[:key_file_exists]).to be true
      end
    end

    context "when no key source is found" do
      before do
        allow(File).to receive(:exist?).and_call_original
        # Mock only the default path to not exist
        allow(File).to receive(:exist?).with(File.expand_path("~/.config/sops/age/keys.txt")).and_return(false)
      end

      it "reports none as key source" do
        info = described_class.info
        expect(info[:key_source]).to eq("none")
        expect(info[:key_file]).to be_nil
        expect(info[:key_file_exists]).to be_nil
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
