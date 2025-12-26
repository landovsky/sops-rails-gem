# frozen_string_literal: true

require "open3"
require "fileutils"
require "yaml"

require_relative "binary"
require_relative "errors"

module SopsRails
  # Interactive setup wizard for initializing sops-rails in a Rails project.
  #
  # This class provides methods to check prerequisites, generate age keys,
  # create configuration files, and set up initial encrypted credentials.
  #
  # @example Basic usage
  #   SopsRails::Init.run
  #
  # @example Non-interactive mode
  #   SopsRails::Init.run(non_interactive: true)
  #
  class Init
    # Get the OS-specific default path for age keys.
    # Delegates to Configuration to ensure consistency.
    #
    # @return [String] Expanded path to default age key location
    #
    def self.age_keys_path
      SopsRails.config.default_age_key_path
    end

    # Gitignore entries to add
    GITIGNORE_ENTRIES = [
      ".env*.local",
      "*.decrypted.*",
      "tmp/secrets/"
    ].freeze

    # Default credentials template
    CREDENTIALS_TEMPLATE = <<~YAML
      # Example credentials structure
      # Replace these with your actual secrets
      aws:
        access_key_id: "your-key-here"
        secret_access_key: "your-secret-here"

      database:
        username: "db_user"
        password: "db_password"

      # Add more credentials as needed
    YAML

    class << self
      # Run the initialization wizard.
      #
      # Checks prerequisites, generates age keys if needed, creates
      # configuration files, and sets up initial encrypted credentials.
      #
      # @param non_interactive [Boolean] If true, skips all prompts and uses defaults
      # @return [void]
      # @raise [SopsNotFoundError] if SOPS binary is not available
      # @raise [AgeNotFoundError] if age binary is not available
      #
      # @example
      #   SopsRails::Init.run
      #
      def run(non_interactive: false)
        puts "Initializing sops-rails for this project..."
        puts

        check_prerequisites
        public_key = ensure_age_key(non_interactive: non_interactive)
        create_sops_config(public_key, non_interactive: non_interactive)
        update_gitignore(non_interactive: non_interactive)
        create_initial_credentials(non_interactive: non_interactive, public_key: public_key)

        puts
        puts "✓ sops-rails initialized successfully!"
        puts
        puts "Your public key (share with team members):"
        puts "  #{public_key}"
        puts
        puts "Next steps:"
        puts "  1. Share your public key with team members"
        puts "  2. Edit credentials: rails sops:edit"
        puts "  3. View credentials: rails sops:show"
      end

      # Check if required binaries (sops and age) are available.
      #
      # @return [void]
      # @raise [SopsNotFoundError] if SOPS binary is not available
      # @raise [AgeNotFoundError] if age binary is not available
      #
      def check_prerequisites
        unless Binary.available?
          raise SopsNotFoundError,
                "sops binary not found in PATH.\n" \
                "Install with: brew install sops (macOS) or apt install sops (Debian/Ubuntu)"
        end

        unless age_available?
          raise AgeNotFoundError,
                "age binary not found in PATH.\n" \
                "Install with: brew install age (macOS) or apt install age (Debian/Ubuntu)"
        end

        puts "✓ sops binary found (#{Binary.version})"
        puts "✓ age binary found"
      end

      # Check if age binary is available in PATH.
      #
      # @return [Boolean] `true` if age binary is found, `false` otherwise
      #
      def age_available?
        stdout, _stderr, status = Open3.capture3("which", "age")
        status.success? && !stdout.strip.empty?
      end

      # Ensure age key exists, generating one if missing.
      #
      # @param non_interactive [Boolean] If true, generates key without prompting
      # @return [String] The age public key
      # @raise [AgeNotFoundError] if age binary is not available
      #
      def ensure_age_key(non_interactive: false)
        keys_path = age_keys_path

        if File.exist?(keys_path)
          puts "✓ Age key found at #{keys_path}"
          return extract_public_key(keys_path)
        end

        puts "Age key not found. Generating new key pair..." unless non_interactive

        # Create directory if it doesn't exist
        key_dir = File.dirname(keys_path)
        FileUtils.mkdir_p(key_dir)

        # Generate key using age-keygen
        _, stderr, status = Open3.capture3("age-keygen", "-o", keys_path)
        unless status.success?
          raise AgeNotFoundError,
                "Failed to generate age key: #{stderr.strip}"
        end

        puts "✓ Generated age key at #{keys_path}"
        extract_public_key(keys_path)
      end

      # Extract public key from age keys file.
      #
      # @param keys_path [String] Path to age keys file
      # @return [String] The age public key
      # @raise [Error] if public key cannot be extracted
      #
      def extract_public_key(keys_path)
        content = File.read(keys_path)
        # Look for line like: # public key: age1...
        match = content.match(/^# public key: (age1[a-z0-9]+)/)
        raise Error, "Could not extract public key from #{keys_path}" unless match

        match[1]
      end

      # Create `.sops.yaml` configuration file with Rails-friendly rules.
      #
      # @param public_key [String] The age public key to include
      # @param non_interactive [Boolean] If true, overwrites existing file without prompting
      # @return [void]
      #
      def create_sops_config(public_key, non_interactive: false)
        sops_yaml_path = ".sops.yaml"

        if File.exist?(sops_yaml_path) && !non_interactive
          print ".sops.yaml already exists. Overwrite? [y/N] "
          response = $stdin.gets.chomp.downcase
          unless %w[y yes].include?(response)
            puts "Skipping .sops.yaml creation"
            return
          end
        end

        config = {
          "creation_rules" => [
            {
              "path_regex" => "config/credentials(\\..*)?\\.yaml\\.enc$",
              "age" => [public_key]
            },
            {
              "path_regex" => "\\.env(\\..*)?\\.enc$",
              "age" => [public_key]
            },
            {
              "path_regex" => ".*",
              "age" => ""
            }
          ]
        }

        File.write(sops_yaml_path, YAML.dump(config))
        puts "✓ Created .sops.yaml"
      end

      # Update `.gitignore` with sops-rails entries.
      #
      # @param non_interactive [Boolean] If true, adds entries without prompting
      # @return [void]
      #
      def update_gitignore(non_interactive: false)
        gitignore_path = ".gitignore"
        existing_content = File.exist?(gitignore_path) ? File.read(gitignore_path) : ""

        # Check which entries are missing
        missing_entries = GITIGNORE_ENTRIES.reject do |entry|
          existing_content.include?(entry)
        end

        return if missing_entries.empty?

        puts "Adding sops-rails entries to .gitignore..." unless non_interactive

        new_content = existing_content.dup
        new_content += "\n" unless new_content.empty? || new_content.end_with?("\n")
        new_content += "\n" unless new_content.empty?
        new_content += "# sops-rails\n"
        missing_entries.each do |entry|
          new_content += "#{entry}\n"
        end

        File.write(gitignore_path, new_content)
        puts "✓ Updated .gitignore"
      end

      # Create initial encrypted credentials file.
      #
      # @param non_interactive [Boolean] If true, overwrites existing file without prompting
      # @param public_key [String] The age public key to encrypt with (bypasses .sops.yaml matching)
      # @return [void]
      # @raise [SopsNotFoundError] if SOPS binary is not available
      # @raise [EncryptionError] if encryption fails
      #
      def create_initial_credentials(non_interactive: false, public_key: nil)
        credentials_path = "config/credentials.yaml.enc"
        credentials_dir = File.dirname(credentials_path)

        # Create config directory if it doesn't exist
        FileUtils.mkdir_p(credentials_dir)

        if File.exist?(credentials_path) && !non_interactive
          print "#{credentials_path} already exists. Overwrite? [y/N] "
          response = $stdin.gets.chomp.downcase
          unless %w[y yes].include?(response)
            puts "Skipping credentials file creation"
            return
          end
        end

        # Write template to temporary file, encrypt it, then remove temp file
        temp_file = "#{credentials_path}.tmp"
        begin
          File.write(temp_file, CREDENTIALS_TEMPLATE)

          # Encrypt using SOPS with explicit age key to avoid .sops.yaml pattern matching issues
          # (temp file name doesn't match the credentials regex pattern)
          sops_args = ["sops", "-e", "-i"]
          sops_args.push("--age", public_key) if public_key
          sops_args.push(temp_file)

          stdout, stderr, status = Open3.capture3(*sops_args)
          unless status.success?
            error_message = stderr.strip.empty? ? stdout.strip : stderr.strip
            raise EncryptionError,
                  "Failed to encrypt credentials file: #{error_message}"
          end

          # Move encrypted file to final location
          FileUtils.mv(temp_file, credentials_path)
          puts "✓ Created #{credentials_path}"
        ensure
          # Clean up temp file if it still exists
          FileUtils.rm_f(temp_file)
        end
      end
    end
  end
end
