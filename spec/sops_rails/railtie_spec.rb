# frozen_string_literal: true

# Require Rails BEFORE spec_helper to ensure Rails is defined
# when sops_rails.rb conditionally requires the railtie
begin
  require "rails"
  require "rails/railtie"
rescue LoadError
  # Rails not available - skip tests
end

require "spec_helper"

# Manually require the railtie file for testing since it's conditionally loaded
# In a real Rails app, this would be loaded automatically via lib/sops_rails.rb
# when Rails is defined
require "sops_rails/railtie" if defined?(Rails)

# Only run tests if Rails is available
if defined?(Rails) && defined?(SopsRails::Railtie)

  RSpec.describe SopsRails::Railtie do
    before do
      SopsRails.reset!
    end

    describe "class definition" do
      it "inherits from Rails::Railtie" do
        expect(described_class.superclass).to eq(Rails::Railtie)
      end

      it "is defined" do
        expect(described_class).to be_a(Class)
      end
    end

    describe "Rails integration" do
      # These tests verify that the Railtie can be loaded and that
      # SopsRails.credentials is accessible in a Rails-like context.
      # Full integration testing would require a complete Rails app,
      # which is beyond the scope of unit tests.

      it "makes SopsRails.credentials accessible when Rails is defined" do
        # Even though Rails is loaded, credentials should still work
        # (lazy loading ensures no errors if files don't exist)
        expect(SopsRails).to respond_to(:credentials)
      end
    end

    describe "conditional loading" do
      it "loads when Rails is defined" do
        # The railtie should be loadable when Rails is available
        expect(defined?(SopsRails::Railtie)).to be_truthy
        expect(SopsRails::Railtie).to be_a(Class)
      end
    end

    describe "acceptance criteria for 1.4 Rails Integration (Railtie)" do
      describe "gem loads automatically in Rails application" do
        it "Railtie is registered with Rails" do
          # Rails::Railtie subclasses are automatically registered
          expect(Rails::Railtie.subclasses).to include(SopsRails::Railtie)
        end

        it "is loaded when Rails is defined" do
          expect(defined?(SopsRails::Railtie)).to eq("constant")
        end
      end

      describe "SopsRails.credentials accessible in Rails console" do
        it "responds to credentials method" do
          expect(SopsRails).to respond_to(:credentials)
        end

        it "can be called after Rails is loaded" do
          # Configure to use non-existent path to test lazy loading
          SopsRails.configure do |config|
            config.encrypted_path = "nonexistent/path"
          end

          # Should not raise - lazy loading with no files returns empty credentials
          expect { SopsRails.credentials }.not_to raise_error
        end
      end

      describe "SopsRails.credentials accessible in initializers" do
        it "works before credentials are accessed" do
          SopsRails.reset!
          # Simulating initializer access - should work immediately after gem load
          expect(SopsRails).to respond_to(:configure)
          expect(SopsRails).to respond_to(:config)
          expect(SopsRails).to respond_to(:credentials)
        end

        it "allows configuration before credential access" do
          SopsRails.configure do |config|
            config.encrypted_path = "custom/secrets"
            config.credential_files = ["app_secrets.yaml.enc"]
          end

          expect(SopsRails.config.encrypted_path).to eq("custom/secrets")
          expect(SopsRails.config.credential_files).to eq(["app_secrets.yaml.enc"])
        end
      end

      describe "ERB interpolation works in database.yml" do
        # This tests that SopsRails.credentials can be called from ERB contexts
        # like database.yml, which is processed early in Rails boot.
        # The actual ERB evaluation happens during YAML processing.

        it "credentials are available for ERB evaluation" do
          # Simulate what happens in database.yml ERB
          # <%= SopsRails.credentials.database.password %>
          expect(SopsRails).to respond_to(:credentials)
        end

        it "returns nil for missing credentials without error" do
          # In database.yml: <%= SopsRails.credentials.database&.password || 'default' %>
          SopsRails.configure { |c| c.encrypted_path = "nonexistent" }

          credentials = SopsRails.credentials
          # NullCredentials allows chaining without raising
          result = credentials.database.password
          expect(result).to be_nil
        end

        it "credentials can be converted to string for ERB output" do
          SopsRails.configure { |c| c.encrypted_path = "nonexistent" }

          credentials = SopsRails.credentials
          # ERB converts result to string
          result = credentials.database.password.to_s
          expect(result).to eq("")
        end

        it "returns actual values when credentials exist" do
          # Mock successful decryption
          yaml_content = <<~YAML
            database:
              host: localhost
              password: secret123
          YAML

          allow(SopsRails::Binary).to receive(:decrypt).and_return(yaml_content)

          # Use a temp directory that we can create a fake file reference for
          Dir.mktmpdir do |tmpdir|
            SopsRails.configure do |config|
              config.encrypted_path = tmpdir
              config.credential_files = ["credentials.yaml.enc"]
            end

            # Create a file so File.exist? returns true
            File.write(File.join(tmpdir, "credentials.yaml.enc"), "encrypted content")

            # Now ERB interpolation like <%= SopsRails.credentials.database.password %>
            expect(SopsRails.credentials.database.password).to eq("secret123")
          end
        end
      end

      describe "no errors when gem loads without credentials file (lazy loading)" do
        it "does not raise error when accessing credentials with no file" do
          SopsRails.configure { |c| c.encrypted_path = "path/that/does/not/exist" }

          expect { SopsRails.credentials }.not_to raise_error
        end

        it "returns empty credentials when no files exist" do
          SopsRails.configure do |config|
            config.encrypted_path = "path/that/does/not/exist"
            config.credential_files = ["nonexistent.yaml.enc"]
          end

          credentials = SopsRails.credentials
          expect(credentials).to be_empty
          expect(credentials.keys).to eq([])
        end

        it "allows chained access on empty credentials" do
          SopsRails.configure { |c| c.encrypted_path = "nonexistent" }

          # Should not raise NoMethodError
          expect { SopsRails.credentials.any.nested.key }.not_to raise_error
          expect(SopsRails.credentials.any.nested.key).to be_nil
        end

        it "configuration can be changed before first credential access" do
          # This is typical initializer pattern
          SopsRails.configure do |config|
            config.encrypted_path = "initial/path"
          end

          SopsRails.configure do |config|
            config.encrypted_path = "updated/path"
          end

          expect(SopsRails.config.encrypted_path).to eq("updated/path")
        end
      end
    end
  end
else
  # Skip tests if Rails is not available
  RSpec.describe "SopsRails::Railtie" do
    it "skips tests when Rails is not available" do
      skip "Rails is not available in this environment"
    end
  end
end
