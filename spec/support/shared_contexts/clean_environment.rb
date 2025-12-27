# frozen_string_literal: true

RSpec.shared_context "with clean environment" do
  around do |example|
    original = {
      "SOPS_AGE_KEY" => ENV.fetch("SOPS_AGE_KEY", nil),
      "SOPS_AGE_KEY_FILE" => ENV.fetch("SOPS_AGE_KEY_FILE", nil),
      "SOPS_RAILS_DEBUG" => ENV.fetch("SOPS_RAILS_DEBUG", nil),
      "RAILS_ENV" => ENV.fetch("RAILS_ENV", nil)
    }
    original.each_key { |k| ENV.delete(k) }
    SopsRails.reset!

    example.run
  ensure
    original.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
    SopsRails.reset!
  end
end
