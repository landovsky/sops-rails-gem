# frozen_string_literal: true

RSpec.describe SopsRails do
  before do
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
