# frozen_string_literal: true

require "spec_helper"

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
    around do |example|
      original_age_key_file = ENV["SOPS_AGE_KEY_FILE"]
      original_age_key = ENV["SOPS_AGE_KEY"]

      example.run

      ENV["SOPS_AGE_KEY_FILE"] = original_age_key_file
      ENV["SOPS_AGE_KEY"] = original_age_key
    end

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
      ENV.delete("SOPS_AGE_KEY_FILE")
      ENV.delete("SOPS_AGE_KEY")
      SopsRails.reset!

      expect(SopsRails.config.age_key_file).to be_nil
      expect(SopsRails.config.age_key).to be_nil
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

  describe "acceptance criteria" do
    it "satisfies: SopsRails.configure { |c| c.encrypted_path = 'custom' } sets the path" do
      SopsRails.configure { |c| c.encrypted_path = "custom" }
      expect(SopsRails.config.encrypted_path).to eq("custom")
    end

    it "satisfies: SopsRails.config.encrypted_path returns configured value" do
      SopsRails.configure { |c| c.encrypted_path = "test_path" }
      expect(SopsRails.config.encrypted_path).to eq("test_path")
    end

    it "satisfies: SopsRails.config.credential_files returns array of file patterns" do
      files = ["credentials.yaml.enc", "secrets.yaml.enc"]
      SopsRails.configure { |c| c.credential_files = files }
      expect(SopsRails.config.credential_files).to eq(files)
      expect(SopsRails.config.credential_files).to be_an(Array)
    end

    it "satisfies: Default values are applied when no configuration block provided" do
      # Reset to ensure clean state
      SopsRails.reset!

      expect(SopsRails.config.encrypted_path).to eq("config")
      expect(SopsRails.config.credential_files).to eq(["credentials.yaml.enc"])
    end

    it "satisfies: Configuration is accessible from any Rails context" do
      # Simulate different contexts by calling from different scopes
      config1 = SopsRails.config
      config2 = -> { SopsRails.config }.call

      # Simulate calling from a module context
      test_module = Module.new do
        extend self

        def fetch_config
          SopsRails.config
        end
      end
      config3 = test_module.fetch_config

      expect(config1).to be(config2)
      expect(config2).to be(config3)
    end
  end
end
