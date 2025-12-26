# frozen_string_literal: true

RSpec.describe SopsRails do
  # Store original env vars and restore after all tests
  around do |example|
    original_debug = ENV.fetch("SOPS_RAILS_DEBUG", nil)
    original_age_key = ENV.fetch("SOPS_AGE_KEY", nil)
    original_age_key_file = ENV.fetch("SOPS_AGE_KEY_FILE", nil)

    # Clear env vars for isolation
    ENV.delete("SOPS_RAILS_DEBUG")
    ENV.delete("SOPS_AGE_KEY")
    ENV.delete("SOPS_AGE_KEY_FILE")
    SopsRails.reset!

    example.run

    # Restore
    ENV["SOPS_RAILS_DEBUG"] = original_debug if original_debug
    ENV["SOPS_AGE_KEY"] = original_age_key if original_age_key
    ENV["SOPS_AGE_KEY_FILE"] = original_age_key_file if original_age_key_file
    ENV.delete("SOPS_RAILS_DEBUG") unless original_debug
    ENV.delete("SOPS_AGE_KEY") unless original_age_key
    ENV.delete("SOPS_AGE_KEY_FILE") unless original_age_key_file
    SopsRails.reset!
  end

  it "has a version number" do
    expect(SopsRails::VERSION).not_to be nil
  end

  describe ".debug_mode?" do
    it "returns false by default" do
      expect(SopsRails.debug_mode?).to be false
    end

    it "returns true when debug mode is enabled" do
      SopsRails.configure { |c| c.debug_mode = true }
      expect(SopsRails.debug_mode?).to be true
    end
  end

  describe ".debug_info" do
    before do
      allow(SopsRails::Binary).to receive(:available?).and_return(true)
      allow(SopsRails::Binary).to receive(:version).and_return("3.8.1")
      allow(Open3).to receive(:capture3).with("which", "age").and_return(["/usr/bin/age", "", double(success?: true)])
      # Mock default key path to not exist
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(SopsRails.config.default_age_key_path).and_return(false)
    end

    it "returns debug information hash" do
      info = SopsRails.debug_info
      expect(info).to be_a(Hash)
      expect(info).to have_key(:key_source)
      expect(info).to have_key(:sops_version)
      expect(info).to have_key(:age_available)
      expect(info).to have_key(:config)
      expect(info).to have_key(:credential_files)
    end

    it "delegates to Debug.info" do
      expect(SopsRails::Debug).to receive(:info).and_return({ test: "data" })
      expect(SopsRails.debug_info).to eq({ test: "data" })
    end
  end
end
