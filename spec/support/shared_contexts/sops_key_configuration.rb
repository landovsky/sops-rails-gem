# frozen_string_literal: true

RSpec.shared_context "with age key file configured" do
  let(:test_key_file) { "/tmp/test_keys.txt" }
  let(:expanded_key_file) { File.expand_path(test_key_file) }

  before do
    ENV["SOPS_AGE_KEY_FILE"] = test_key_file
    SopsRails.reset!
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(expanded_key_file).and_return(true)
  end
end

RSpec.shared_context "with inline age key configured" do
  let(:test_age_key) { "AGE-SECRET-KEY-1TESTKEY..." }

  before do
    ENV["SOPS_AGE_KEY"] = test_age_key
    SopsRails.reset!
  end
end
