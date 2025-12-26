# frozen_string_literal: true

require "open3"

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
        status.success? && !stdout.strip.empty?
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

        stdout, stderr, status = Open3.capture3("sops", "--version")
        raise SopsNotFoundError, "failed to get sops version: #{stderr.strip}" unless status.success?

        # Parse version from output like "sops 3.8.1" or "3.8.1"
        version_match = stdout.match(/(\d+\.\d+\.\d+)/)
        raise SopsNotFoundError, "unable to parse sops version from: #{stdout.strip}" unless version_match

        version_match[1]
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

        stdout, stderr, status = Open3.capture3("sops", "-d", file_path.to_s)
        unless status.success?
          error_message = stderr.strip.empty? ? stdout.strip : stderr.strip
          raise DecryptionError, "failed to decrypt file #{file_path}: #{error_message}"
        end

        stdout
      end
    end
  end
end
