# frozen_string_literal: true

RSpec.shared_examples "a valid SOPS encrypted file" do |file_path|
  it "contains sops metadata key" do
    content = File.read(file_path)
    parsed = YAML.safe_load(content, permitted_classes: [Time])
    expect(parsed).to have_key("sops")
  end

  it "has valid SOPS metadata structure" do
    content = File.read(file_path)
    parsed = YAML.safe_load(content, permitted_classes: [Time])
    sops_meta = parsed["sops"]

    expect(sops_meta).to have_key("mac")
    expect(sops_meta).to have_key("lastmodified")
    expect(sops_meta).to have_key("version")
  end

  it "passes sops --file-status check", :integration do
    _stdout, stderr, status = Open3.capture3("sops", "--file-status", file_path)
    expect(status.success?).to be(true), "sops --file-status failed: #{stderr}"
  end

  it "can be decrypted", :integration do
    expect { SopsRails::Binary.decrypt(file_path) }.not_to raise_error
  end
end
