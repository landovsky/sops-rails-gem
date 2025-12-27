# frozen_string_literal: true

require "spec_helper"

RSpec.shared_context "with clean ENV" do
  around do |example|
    original = {
      "SOPS_AGE_KEY" => ENV.fetch("SOPS_AGE_KEY", nil),
      "SOPS_AGE_KEY_FILE" => ENV.fetch("SOPS_AGE_KEY_FILE", nil),
      "SOPS_RAILS_DEBUG" => ENV.fetch("SOPS_RAILS_DEBUG", nil)
    }
    original.each_key { |k| ENV.delete(k) }
    SopsRails.reset!

    example.run
  ensure
    original.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
    SopsRails.reset!
  end
end

RSpec.shared_examples "treats empty string as nil" do |env_var, config_method|
  it "treats empty string as nil for #{env_var}" do
    ENV[env_var] = ""
    SopsRails.reset!
    expect(SopsRails.config.public_send(config_method)).to be_nil
  end
end

RSpec.describe SopsRails::Configuration do
  # Reset configuration before each test to ensure isolation
  before do
    SopsRails.reset!
  end

  describe ".configure" do
    it "allows block-style configuration" do
      SopsRails.configure do |config|
        config.encrypted_path = "custom"
        config.credential_files = ["custom.yaml.enc"]
      end

      expect(SopsRails.config.encrypted_path).to eq("custom")
      expect(SopsRails.config.credential_files).to eq(["custom.yaml.enc"])
    end

    it "returns the configuration instance" do
      config = SopsRails.configure do |c|
        c.encrypted_path = "test"
      end

      expect(config).to be_a(SopsRails::Configuration)
      expect(config.encrypted_path).to eq("test")
    end

    it "works without a block" do
      config = SopsRails.configure
      expect(config).to be_a(SopsRails::Configuration)
    end
  end

  describe ".config" do
    it "returns a Configuration instance" do
      expect(SopsRails.config).to be_a(SopsRails::Configuration)
    end

    it "returns the same instance on subsequent calls" do
      config1 = SopsRails.config
      config2 = SopsRails.config
      expect(config1).to be(config2)
    end

    it "returns default values when no configuration provided" do
      expect(SopsRails.config.encrypted_path).to eq("config")
      expect(SopsRails.config.credential_files).to eq(["credentials.yaml.enc"])
    end
  end

  describe "default values" do
    it "has encrypted_path default of 'config'" do
      expect(SopsRails.config.encrypted_path).to eq("config")
    end

    it "has credential_files default of ['credentials.yaml.enc']" do
      expect(SopsRails.config.credential_files).to eq(["credentials.yaml.enc"])
    end
  end

  describe "environment variables" do
    include_context "with clean ENV"

    it "reads SOPS_AGE_KEY_FILE environment variable" do
      ENV["SOPS_AGE_KEY_FILE"] = "/path/to/key.txt"
      SopsRails.reset!

      expect(SopsRails.config.age_key_file).to eq("/path/to/key.txt")
    end

    it "reads SOPS_AGE_KEY environment variable" do
      ENV["SOPS_AGE_KEY"] = "AGE-SECRET-KEY-1ABC123..."
      SopsRails.reset!

      expect(SopsRails.config.age_key).to eq("AGE-SECRET-KEY-1ABC123...")
    end

    it "returns nil when environment variables are not set" do
      expect(SopsRails.config.age_key_file).to be_nil
      expect(SopsRails.config.age_key).to be_nil
    end

    include_examples "treats empty string as nil", "SOPS_AGE_KEY_FILE", :age_key_file
    include_examples "treats empty string as nil", "SOPS_AGE_KEY", :age_key

    it "reads SOPS_RAILS_DEBUG environment variable" do
      ENV["SOPS_RAILS_DEBUG"] = "1"
      SopsRails.reset!

      expect(SopsRails.config.debug_mode).to be true
    end

    it "treats '0' as false for SOPS_RAILS_DEBUG" do
      ENV["SOPS_RAILS_DEBUG"] = "0"
      SopsRails.reset!

      expect(SopsRails.config.debug_mode).to be false
    end

    it "treats 'false' as false for SOPS_RAILS_DEBUG" do
      ENV["SOPS_RAILS_DEBUG"] = "false"
      SopsRails.reset!

      expect(SopsRails.config.debug_mode).to be false
    end

    it "treats empty string as false for SOPS_RAILS_DEBUG" do
      ENV["SOPS_RAILS_DEBUG"] = ""
      SopsRails.reset!

      expect(SopsRails.config.debug_mode).to be false
    end

    it "defaults to false when SOPS_RAILS_DEBUG is not set" do
      expect(SopsRails.config.debug_mode).to be false
    end
  end

  describe "debug_mode" do
    it "allows setting debug_mode via configuration" do
      SopsRails.configure do |config|
        config.debug_mode = true
      end

      expect(SopsRails.config.debug_mode).to be true
    end

    it "allows disabling debug_mode via configuration" do
      SopsRails.configure do |config|
        config.debug_mode = false
      end

      expect(SopsRails.config.debug_mode).to be false
    end
  end

  describe "thread safety" do
    it "safely handles concurrent configuration updates" do
      threads = []
      results = []

      10.times do |i|
        threads << Thread.new do
          SopsRails.configure do |config|
            config.encrypted_path = "thread-#{i}"
            sleep(0.01) # Simulate some work
            results << config.encrypted_path
          end
        end
      end

      threads.each(&:join)

      # All threads should have completed without errors
      expect(results.length).to eq(10)
    end

    it "maintains configuration consistency across threads" do
      SopsRails.configure do |config|
        config.encrypted_path = "shared"
      end

      threads = []
      results = []

      5.times do
        threads << Thread.new do
          results << SopsRails.config.encrypted_path
        end
      end

      threads.each(&:join)

      # All threads should see the same configuration
      expect(results.uniq).to eq(["shared"])
    end
  end

  describe "attribute accessors" do
    it "allows setting and getting encrypted_path" do
      SopsRails.configure do |config|
        config.encrypted_path = "custom_path"
      end

      expect(SopsRails.config.encrypted_path).to eq("custom_path")
    end

    it "allows setting and getting credential_files" do
      files = ["file1.yaml.enc", "file2.yaml.enc"]
      SopsRails.configure do |config|
        config.credential_files = files
      end

      expect(SopsRails.config.credential_files).to eq(files)
    end

    it "allows setting credential_files to a different array" do
      SopsRails.configure do |config|
        config.credential_files = ["first.yaml.enc"]
      end

      expect(SopsRails.config.credential_files).to eq(["first.yaml.enc"])

      SopsRails.configure do |config|
        config.credential_files = ["second.yaml.enc"]
      end

      expect(SopsRails.config.credential_files).to eq(["second.yaml.enc"])
    end
  end

  describe "age key file paths" do
    include_context "with clean ENV"

    describe "#default_age_key_path" do
      it "returns OS-specific path for macOS" do
        allow(SopsRails.config).to receive(:macos?).and_return(true)
        expected = File.expand_path("~/Library/Application Support/sops/age/keys.txt")
        expect(SopsRails.config.default_age_key_path).to eq(expected)
      end

      it "returns XDG path for non-macOS" do
        allow(SopsRails.config).to receive(:macos?).and_return(false)
        expected = File.expand_path("~/.config/sops/age/keys.txt")
        expect(SopsRails.config.default_age_key_path).to eq(expected)
      end
    end

    describe "#resolved_age_key_file" do
      context "when SOPS_AGE_KEY is set" do
        it "returns nil (inline key doesn't need a file)" do
          ENV["SOPS_AGE_KEY"] = "AGE-SECRET-KEY-1ABC123"
          SopsRails.reset!
          expect(SopsRails.config.resolved_age_key_file).to be_nil
        end
      end

      context "when SOPS_AGE_KEY_FILE is set to existing file" do
        it "returns the expanded path" do
          ENV["SOPS_AGE_KEY_FILE"] = "/path/to/key.txt"
          SopsRails.reset!
          expanded = File.expand_path("/path/to/key.txt")
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(expanded).and_return(true)
          expect(SopsRails.config.resolved_age_key_file).to eq(expanded)
        end
      end

      context "when SOPS_AGE_KEY_FILE is set to non-existing file" do
        it "falls back to default location" do
          ENV["SOPS_AGE_KEY_FILE"] = "/nonexistent/key.txt"
          SopsRails.reset!
          expanded = File.expand_path("/nonexistent/key.txt")
          default_path = SopsRails.config.default_age_key_path
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(expanded).and_return(false)
          allow(File).to receive(:exist?).with(default_path).and_return(true)
          expect(SopsRails.config.resolved_age_key_file).to eq(default_path)
        end
      end

      context "when no key file is found" do
        it "returns nil" do
          default_path = SopsRails.config.default_age_key_path
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(default_path).and_return(false)
          expect(SopsRails.config.resolved_age_key_file).to be_nil
        end
      end
    end

    describe "#public_key" do
      context "when key file exists with public key comment" do
        it "extracts the public key" do
          default_path = SopsRails.config.default_age_key_path
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(default_path).and_return(true)
          allow(File).to receive(:foreach).with(default_path)
                                          .and_yield("# created: 2024-01-01T00:00:00Z")
                                          .and_yield("# public key: age1abcdefghijklmnop")
                                          .and_yield("AGE-SECRET-KEY-...")
          expect(SopsRails.config.public_key).to eq("age1abcdefghijklmnop")
        end
      end

      context "when key file does not exist" do
        it "returns nil" do
          default_path = SopsRails.config.default_age_key_path
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(default_path).and_return(false)
          expect(SopsRails.config.public_key).to be_nil
        end
      end
    end
  end
end
