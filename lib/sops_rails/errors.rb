# frozen_string_literal: true

module SopsRails
  # Base error class for all sops_rails errors.
  #
  # All specific error types inherit from this class.
  #
  # @example
  #   raise SopsRails::Error, "Something went wrong"
  #
  class Error < StandardError; end

  # Raised when SOPS binary is not found in PATH.
  #
  # This error is raised when attempting to use SOPS functionality
  # but the `sops` binary cannot be located.
  #
  # @example
  #   raise SopsRails::SopsNotFoundError, "sops binary not found in PATH"
  #
  class SopsNotFoundError < Error; end

  # Raised when SOPS decryption fails.
  #
  # This error is raised when SOPS cannot decrypt a file, typically
  # due to missing or incorrect keys, corrupted files, or other
  # decryption-related issues.
  #
  # @example
  #   raise SopsRails::DecryptionError, "Failed to decrypt file: #{file_path}"
  #
  class DecryptionError < Error; end

  # Raised when age binary is not found in PATH.
  #
  # This error is raised when attempting to generate age keys
  # but the `age` binary cannot be located.
  #
  # @example
  #   raise SopsRails::AgeNotFoundError, "age binary not found in PATH"
  #
  class AgeNotFoundError < Error; end

  # Raised when SOPS encryption fails.
  #
  # This error is raised when SOPS cannot encrypt a file, typically
  # due to missing or incorrect configuration in .sops.yaml.
  #
  # @example
  #   raise SopsRails::EncryptionError, "Failed to encrypt file: #{file_path}"
  #
  class EncryptionError < Error; end
end
