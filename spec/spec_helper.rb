# frozen_string_literal: true

require "sops_rails"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Integration tests run by default, but skip gracefully when prerequisites missing
  # Use SKIP_INTEGRATION=1 to exclude them entirely (e.g., in CI without SOPS)
  config.filter_run_excluding integration: true if ENV["SKIP_INTEGRATION"] == "1"

  # Auto-skip integration tests when SOPS is not available
  # This allows tests to be written but skipped gracefully
  config.before(:example, :integration) do |example|
    unless SopsRails::Binary.available?
      skip "SOPS binary not available (install SOPS to run integration tests)"
    end
  end
end
