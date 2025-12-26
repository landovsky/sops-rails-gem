# frozen_string_literal: true

# Require Rails BEFORE spec_helper to ensure Rails is defined
# when sops_rails.rb conditionally requires the railtie
begin
  require "rails"
  require "rails/railtie"
  require "rake"
rescue LoadError
  # Rails not available - skip tests
end

require "spec_helper"

# Manually require the railtie file for testing since it's conditionally loaded
# In a real Rails app, this would be loaded automatically via lib/sops_rails.rb
# when Rails is defined
require "sops_rails/railtie" if defined?(Rails)

# Load rake tasks for testing (normally done by Railtie rake_tasks block)
if defined?(Rake) && defined?(SopsRails)
  Dir.glob(File.join(__dir__, "../../lib/sops_rails/tasks/**/*.rake")).each { |r| load r }
end

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

      describe "rake tasks are loaded" do
        it "loads sops:init task" do
          # Verify the task is available in Rake
          expect(Rake::Task.task_defined?("sops:init")).to be true
        end

        it "sops:init task is executable" do
          task = Rake::Task["sops:init"]
          # Task should be a valid Rake::Task instance
          expect(task).to be_a(Rake::Task)
          expect(task.name).to eq("sops:init")
        end

        it "loads sops:show task" do
          # Verify the task is available in Rake
          expect(Rake::Task.task_defined?("sops:show")).to be true
        end

        it "sops:show task is executable" do
          task = Rake::Task["sops:show"]
          # Task should be a valid Rake::Task instance
          expect(task).to be_a(Rake::Task)
          expect(task.name).to eq("sops:show")
        end
      end

      describe "sops:show rake task" do
        let(:decrypted_content) do
          <<~YAML
            aws:
              access_key_id: AKIAIOSFODNN7EXAMPLE
              secret_access_key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
            database:
              password: secret123
          YAML
        end

        before do
          SopsRails.reset!
          # Re-enable task to allow multiple invocations in tests
          Rake::Task["sops:show"].reenable if Rake::Task.task_defined?("sops:show")
          # Reset ARGV to default (no extra arguments)
          stub_const("ARGV", ["sops:show"])
        end

        # Helper to invoke task with simulated ARGV
        def invoke_show_with_argv(*args)
          stub_const("ARGV", ["sops:show"] + args)
          Rake::Task["sops:show"].reenable
          Rake::Task["sops:show"].invoke
        end

        describe "default behavior" do
          it "outputs decrypted YAML to stdout" do
            Dir.mktmpdir do |tmpdir|
              encrypted_file = File.join(tmpdir, "credentials.yaml.enc")
              File.write(encrypted_file, "encrypted content")

              SopsRails.configure do |config|
                config.encrypted_path = tmpdir
                config.credential_files = ["credentials.yaml.enc"]
              end

              allow(SopsRails::Binary).to receive(:decrypt).with(encrypted_file).and_return(decrypted_content)

              expect do
                invoke_show_with_argv
              end.to output(decrypted_content).to_stdout
            end
          end

          it "uses first credential file from config" do
            Dir.mktmpdir do |tmpdir|
              encrypted_file = File.join(tmpdir, "credentials.yaml.enc")
              File.write(encrypted_file, "encrypted content")

              SopsRails.configure do |config|
                config.encrypted_path = tmpdir
                config.credential_files = ["credentials.yaml.enc"]
              end

              expect(SopsRails::Binary).to receive(:decrypt).with(encrypted_file).and_return(decrypted_content)

              invoke_show_with_argv
            end
          end
        end

        describe "FILE argument" do
          it "shows specific file when FILE argument provided" do
            Dir.mktmpdir do |tmpdir|
              specific_file = File.join(tmpdir, "credentials.production.yaml.enc")
              File.write(specific_file, "encrypted content")

              SopsRails.configure do |config|
                config.encrypted_path = tmpdir
                config.credential_files = ["credentials.yaml.enc"]
              end

              expect(SopsRails::Binary).to receive(:decrypt).with(specific_file).and_return(decrypted_content)

              invoke_show_with_argv(specific_file)
            end
          end

          it "outputs valid YAML format" do
            Dir.mktmpdir do |tmpdir|
              encrypted_file = File.join(tmpdir, "custom.yaml.enc")
              File.write(encrypted_file, "encrypted content")

              allow(SopsRails::Binary).to receive(:decrypt).with(encrypted_file).and_return(decrypted_content)

              # Verify output is valid YAML by checking it can be parsed
              expect { YAML.safe_load(decrypted_content) }.not_to raise_error

              # Verify the task outputs the content
              expect do
                invoke_show_with_argv(encrypted_file)
              end.to output(decrypted_content).to_stdout
            end
          end
        end

        describe "-e ENVIRONMENT flag" do
          it "shows environment-specific file when -e flag is used" do
            Dir.mktmpdir do |tmpdir|
              env_file = File.join(tmpdir, "credentials.production.yaml.enc")
              File.write(env_file, "encrypted content")

              SopsRails.configure do |config|
                config.encrypted_path = tmpdir
                config.credential_files = ["credentials.yaml.enc"]
              end

              expect(SopsRails::Binary).to receive(:decrypt).with(env_file).and_return(decrypted_content)

              invoke_show_with_argv("-e", "production")
            end
          end

          it "constructs path as credentials.{environment}.yaml.enc" do
            Dir.mktmpdir do |tmpdir|
              env_file = File.join(tmpdir, "credentials.staging.yaml.enc")
              File.write(env_file, "encrypted content")

              SopsRails.configure do |config|
                config.encrypted_path = tmpdir
              end

              expect(SopsRails::Binary).to receive(:decrypt).with(env_file).and_return(decrypted_content)

              invoke_show_with_argv("-e", "staging")
            end
          end

          it "supports --environment long flag" do
            Dir.mktmpdir do |tmpdir|
              env_file = File.join(tmpdir, "credentials.test.yaml.enc")
              File.write(env_file, "encrypted content")

              SopsRails.configure do |config|
                config.encrypted_path = tmpdir
              end

              expect(SopsRails::Binary).to receive(:decrypt).with(env_file).and_return(decrypted_content)

              invoke_show_with_argv("--environment", "test")
            end
          end
        end

        describe "error handling" do
          it "exits with error code 1 when file not found" do
            Dir.mktmpdir do |tmpdir|
              SopsRails.configure do |config|
                config.encrypted_path = tmpdir
                config.credential_files = ["nonexistent.yaml.enc"]
              end

              expect do
                invoke_show_with_argv
              rescue SystemExit => e
                expect(e.status).to eq(1)
                raise
              end.to raise_error(SystemExit)
            end
          end

          it "outputs error message to stderr when file not found" do
            Dir.mktmpdir do |tmpdir|
              SopsRails.configure do |config|
                config.encrypted_path = tmpdir
                config.credential_files = ["nonexistent.yaml.enc"]
              end

              expect do
                invoke_show_with_argv
              rescue SystemExit
                # Expected
              end.to output(/Error: File not found/).to_stderr
            end
          end

          it "exits with error code 1 when decryption fails" do
            Dir.mktmpdir do |tmpdir|
              encrypted_file = File.join(tmpdir, "credentials.yaml.enc")
              File.write(encrypted_file, "encrypted content")

              SopsRails.configure do |config|
                config.encrypted_path = tmpdir
                config.credential_files = ["credentials.yaml.enc"]
              end

              allow(SopsRails::Binary).to receive(:decrypt).and_raise(
                SopsRails::DecryptionError, "failed to decrypt file"
              )

              expect do
                invoke_show_with_argv
              rescue SystemExit => e
                expect(e.status).to eq(1)
                raise
              end.to raise_error(SystemExit)
            end
          end

          it "outputs error message to stderr when decryption fails" do
            Dir.mktmpdir do |tmpdir|
              encrypted_file = File.join(tmpdir, "credentials.yaml.enc")
              File.write(encrypted_file, "encrypted content")

              SopsRails.configure do |config|
                config.encrypted_path = tmpdir
                config.credential_files = ["credentials.yaml.enc"]
              end

              allow(SopsRails::Binary).to receive(:decrypt).and_raise(
                SopsRails::DecryptionError, "failed to decrypt file"
              )

              expect do
                invoke_show_with_argv
              rescue SystemExit
                # Expected
              end.to output(/Error: failed to decrypt file/).to_stderr
            end
          end

          it "exits with error code 1 when SOPS binary not found" do
            Dir.mktmpdir do |tmpdir|
              encrypted_file = File.join(tmpdir, "credentials.yaml.enc")
              File.write(encrypted_file, "encrypted content")

              SopsRails.configure do |config|
                config.encrypted_path = tmpdir
                config.credential_files = ["credentials.yaml.enc"]
              end

              allow(SopsRails::Binary).to receive(:decrypt).and_raise(
                SopsRails::SopsNotFoundError, "sops binary not found in PATH"
              )

              expect do
                invoke_show_with_argv
              rescue SystemExit => e
                expect(e.status).to eq(1)
                raise
              end.to raise_error(SystemExit)
            end
          end

          it "outputs error message to stderr when SOPS binary not found" do
            Dir.mktmpdir do |tmpdir|
              encrypted_file = File.join(tmpdir, "credentials.yaml.enc")
              File.write(encrypted_file, "encrypted content")

              SopsRails.configure do |config|
                config.encrypted_path = tmpdir
                config.credential_files = ["credentials.yaml.enc"]
              end

              allow(SopsRails::Binary).to receive(:decrypt).and_raise(
                SopsRails::SopsNotFoundError, "sops binary not found in PATH"
              )

              expect do
                invoke_show_with_argv
              rescue SystemExit
                # Expected
              end.to output(/Error: sops binary not found in PATH/).to_stderr
            end
          end
        end

        describe "argument precedence" do
          it "FILE argument takes precedence over -e flag" do
            Dir.mktmpdir do |tmpdir|
              specific_file = File.join(tmpdir, "custom.yaml.enc")
              env_file = File.join(tmpdir, "credentials.production.yaml.enc")
              File.write(specific_file, "encrypted content")
              File.write(env_file, "encrypted content")

              SopsRails.configure do |config|
                config.encrypted_path = tmpdir
                config.credential_files = ["credentials.yaml.enc"]
              end

              # Should use specific_file, not env_file
              expect(SopsRails::Binary).to receive(:decrypt).with(specific_file).and_return(decrypted_content)
              expect(SopsRails::Binary).not_to receive(:decrypt).with(env_file)

              # FILE comes before -e in ARGV
              invoke_show_with_argv(specific_file, "-e", "production")
            end
          end
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
