# frozen_string_literal: true

require "open3"

require_relative "debug"

module SopsRails
  # Interface for interacting with the SOPS command-line binary.
  #
  # Provides methods to check SOPS availability, get version information,
  # and decrypt encrypted files. All operations are performed via shell
  # execution to the SOPS binary, following ADR-001.
  #
  # Decrypted content is never written to the filesystem (memory-only),
  # following ADR-002.
  #
  # @example Check if SOPS is available
  #   SopsRails::Binary.available? # => true
  #
  # @example Get SOPS version
  #   SopsRails::Binary.version # => "3.8.1"
  #
  # @example Decrypt a file
  #   content = SopsRails::Binary.decrypt("config/credentials.yaml.enc")
  #   # => "aws:\n  access_key_id: ..."
  #
  class Binary
    class << self
      # Check if SOPS binary is available in PATH.
      #
      # @return [Boolean] `true` if SOPS binary is found, `false` otherwise
      #
      # @example
      #   SopsRails::Binary.available? # => true
      #
      def available?
        stdout, _stderr, status = Open3.capture3("which", "sops")
        result = status.success? && !stdout.strip.empty?
        Debug.log("SOPS binary available: #{result}")
        result
      end

      # Get the version of the installed SOPS binary.
      #
      # @return [String] Version string (e.g., "3.8.1")
      # @raise [SopsNotFoundError] if SOPS binary is not available
      #
      # @example
      #   SopsRails::Binary.version # => "3.8.1"
      #
      def version
        raise SopsNotFoundError, "sops binary not found in PATH" unless available?

        Debug.log("Checking SOPS version...")
        stdout, stderr, status = Open3.capture3("sops", "--version")
        handle_version_error(stderr) unless status.success?

        parse_version(stdout)
      end

      # Decrypt a SOPS-encrypted file and return the decrypted content.
      #
      # The decrypted content is captured from stdout and never written to
      # the filesystem (memory-only operation).
      #
      # @param file_path [String] Path to the encrypted file to decrypt
      # @return [String] Decrypted content as a string
      # @raise [SopsNotFoundError] if SOPS binary is not available
      # @raise [DecryptionError] if decryption fails
      #
      # @example
      #   content = SopsRails::Binary.decrypt("config/credentials.yaml.enc")
      #   # => "aws:\n  access_key_id: secret123"
      #
      def decrypt(file_path)
        raise SopsNotFoundError, "sops binary not found in PATH" unless available?

        Debug.log_key_info
        file_path_str = file_path.to_s
        log_decrypt_start(file_path_str)

        env = build_sops_env
        stdout, stderr, status = Open3.capture3(env, "sops", "-d", file_path_str)
        handle_decrypt_result(file_path, stdout, stderr, status)
      end

      # Edit a SOPS-encrypted file using the native SOPS editor integration.
      #
      # Opens the file in the user's preferred editor (determined by $EDITOR
      # environment variable, with fallback to vim/nano). SOPS automatically
      # handles decryption before editing and re-encryption after saving.
      #
      # If the file doesn't exist, SOPS will create it using the encryption
      # rules defined in .sops.yaml.
      #
      # Uses system() to give the editor full control of stdin/stdout/stderr
      # for interactive editing.
      #
      # @param file_path [String] Path to the encrypted file to edit
      # @return [Boolean] `true` if edit was successful, `false` if user aborted
      # @raise [SopsNotFoundError] if SOPS binary is not available
      #
      # @example Edit default credentials
      #   SopsRails::Binary.edit("config/credentials.yaml.enc")
      #   # => true (if user saved) or false (if user aborted)
      #
      def edit(file_path)
        raise SopsNotFoundError, "sops binary not found in PATH" unless available?

        Debug.log_key_info
        file_path_str = file_path.to_s
        Debug.log("Editing file: #{file_path_str}")
        Debug.log("Executing: sops #{file_path_str}")

        env = build_sops_env
        system(env, "sops", file_path_str)
      end

      # Encrypt plain content and write to a file using SOPS.
      #
      # Creates a new encrypted file from plain text content. Uses a temporary
      # file to pass content to SOPS, then writes encrypted output to the target.
      #
      # @param file_path [String] Path where the encrypted file will be created
      # @param content [String] Plain text content to encrypt
      # @param public_key [String, nil] Optional age public key to encrypt for.
      #   If not provided, extracts from config. If nil, SOPS will use .sops.yaml rules.
      # @return [Boolean] `true` if encryption succeeded
      # @raise [SopsNotFoundError] if SOPS binary is not available
      # @raise [EncryptionError] if encryption fails
      #
      # @example Create encrypted credentials file
      #   SopsRails::Binary.encrypt_to_file("config/credentials.yaml.enc", "secret_key_base: abc123")
      #   # => true
      #
      # @example Create with explicit public key
      #   SopsRails::Binary.encrypt_to_file("config/credentials.yaml.enc", "secret_key_base: abc123",
      #                                      public_key: "age1...")
      #   # => true
      #
      def encrypt_to_file(file_path, content, public_key: nil)
        raise SopsNotFoundError, "sops binary not found in PATH" unless available?

        Debug.log_key_info
        file_path_str = file_path.to_s
        Debug.log("Encrypting content to: #{file_path_str}")

        # Auto-detect public key if not explicitly provided
        public_key ||= SopsRails.config.public_key

        require "tempfile"
        encrypt_via_tempfile(file_path_str, content, public_key)
      end

      private

      # Encrypt content using a temporary file and write to target.
      #
      # @param file_path_str [String] Target file path
      # @param content [String] Plain content to encrypt
      # @param public_key [String, nil] Optional age public key to encrypt for
      # @return [Boolean] true on success
      # @raise [EncryptionError] if encryption fails
      #
      def encrypt_via_tempfile(file_path_str, content, public_key)
        extension = determine_temp_file_extension(file_path_str)

        Tempfile.create(["sops_template", extension]) do |temp|
          temp.write(content)
          temp.flush

          sops_args = build_encrypt_command(public_key, temp.path)
          Debug.log("Executing: #{sops_args.join(" ")} > #{file_path_str}")

          env = build_sops_env
          stdout, stderr, status = Open3.capture3(env, *sops_args)
          write_encrypted_output(file_path_str, stdout, stderr, status)
        end
      end

      # Determine the file extension for the temporary file.
      #
      # @param file_path_str [String] Target file path
      # @return [String] File extension (e.g., ".yaml")
      #
      def determine_temp_file_extension(file_path_str)
        extension = File.extname(file_path_str).sub(/\.enc$/, "")
        extension.empty? ? ".yaml" : extension
      end

      # Build the SOPS encryption command arguments.
      #
      # @param public_key [String, nil] Optional age public key
      # @param temp_path [String] Path to temporary file
      # @return [Array<String>] Command arguments
      #
      def build_encrypt_command(public_key, temp_path)
        args = ["sops", "-e"]
        args.push("--age", public_key) if public_key
        args.push(temp_path)
        args
      end

      # Process encryption result and write to target file.
      #
      # @param file_path_str [String] Target file path
      # @param stdout [String] Encrypted content from SOPS
      # @param stderr [String] Error output from SOPS
      # @param status [Process::Status] Exit status
      # @return [Boolean] true on success
      # @raise [EncryptionError] if encryption fails
      #
      def write_encrypted_output(file_path_str, stdout, stderr, status) # rubocop:disable Naming/PredicateMethod
        unless status.success?
          error_message = stderr.strip.empty? ? stdout.strip : stderr.strip
          Debug.log("Encryption failed: #{error_message}")
          raise EncryptionError, "failed to encrypt file #{file_path_str}: #{error_message}"
        end

        File.write(file_path_str, stdout)
        Debug.log("Encryption successful: #{file_path_str}")
        true
      end

      # Build environment variables to pass to SOPS.
      #
      # Sets SOPS_AGE_KEY_FILE if a resolved key file is available,
      # ensuring SOPS uses the same key we detected.
      #
      # @return [Hash] Environment variables for SOPS subprocess
      #
      def build_sops_env
        env = {}
        config = SopsRails.config

        # Pass inline key if available
        env["SOPS_AGE_KEY"] = config.age_key if config.age_key

        # Pass resolved key file path
        key_file = config.resolved_age_key_file
        env["SOPS_AGE_KEY_FILE"] = key_file if key_file

        Debug.log("SOPS env: SOPS_AGE_KEY_FILE=#{key_file || "(not set)"}") if key_file || config.age_key.nil?
        env
      end

      def handle_version_error(stderr)
        Debug.log("SOPS version check failed: #{stderr.strip}")
        raise SopsNotFoundError, "failed to get sops version: #{stderr.strip}"
      end

      def parse_version(stdout)
        version_match = stdout.match(/(\d+\.\d+\.\d+)/)
        unless version_match
          Debug.log("Unable to parse SOPS version from: #{stdout.strip}")
          raise SopsNotFoundError, "unable to parse sops version from: #{stdout.strip}"
        end

        version = version_match[1]
        Debug.log("SOPS version: #{version}")
        version
      end

      def log_decrypt_start(file_path_str)
        Debug.log("Decrypting file: #{file_path_str}")
        Debug.log("Executing: sops -d #{file_path_str}")
      end

      def handle_decrypt_result(file_path, stdout, stderr, status)
        unless status.success?
          error_message = stderr.strip.empty? ? stdout.strip : stderr.strip
          Debug.log("Decryption failed: #{error_message}")
          raise DecryptionError, "failed to decrypt file #{file_path}: #{error_message}"
        end

        Debug.log("Decryption successful for: #{file_path}")
        stdout
      end
    end
  end
end
