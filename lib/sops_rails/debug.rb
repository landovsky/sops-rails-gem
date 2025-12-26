# frozen_string_literal: true

module SopsRails
  # Debug logging and information utilities for sops_rails.
  #
  # Provides methods to log debug information when debug mode is enabled,
  # and to gather structured debug information about the current configuration
  # and key sources.
  #
  # All debug output goes to stderr to avoid interfering with normal operations.
  # Secret values (keys, decrypted content) are never logged.
  #
  # @example Logging debug information
  #   SopsRails::Debug.log("Checking file: config/credentials.yaml.enc")
  #
  # @example Getting debug information
  #   SopsRails::Debug.info
  #   # => { key_source: "SOPS_AGE_KEY_FILE", ... }
  #
  module Debug
    class << self
      # Log a debug message if debug mode is enabled.
      #
      # Messages are written to stderr and only appear when debug mode is active.
      #
      # @param message [String] The message to log
      # @return [void]
      #
      # @example
      #   SopsRails::Debug.log("Decrypting file: config/credentials.yaml.enc")
      #
      def log(message)
        return unless debug_mode?

        warn("[sops_rails] #{message}")
      end

      # Get structured debug information about the current configuration.
      #
      # Returns a hash containing key source information, configuration values,
      # binary availability, and file status. Never includes secret values.
      #
      # @return [Hash] Debug information hash
      #
      # @example
      #   SopsRails::Debug.info
      #   # => {
      #   #   key_source: "SOPS_AGE_KEY_FILE",
      #   #   key_file: "/path/to/key.txt",
      #   #   key_file_exists: true,
      #   #   sops_version: "3.8.1",
      #   #   age_available: true,
      #   #   config: { ... }
      #   # }
      #
      def info
        config = SopsRails.config
        key_info = detect_key_source(config)

        build_info_hash(key_info, config)
      end

      # Check if debug mode is currently enabled.
      #
      # @return [Boolean] true if debug mode is enabled
      #
      def debug_mode?
        SopsRails.config.debug_mode
      end

      private

      # Detect which key source is being used.
      #
      # Priority order:
      # 1. SOPS_AGE_KEY environment variable (if set)
      # 2. SOPS_AGE_KEY_FILE environment variable (if set)
      # 3. Default location: ~/.config/sops/age/keys.txt (if exists)
      # 4. None (SOPS will use .sops.yaml rules)
      #
      # @param config [Configuration] The configuration instance
      # @return [Hash] Key source information
      #
      def detect_key_source(config)
        return key_from_env_var if config.age_key
        return key_from_env_file(config.age_key_file) if config.age_key_file

        key_from_default_location
      end

      def key_from_env_var
        { source: "SOPS_AGE_KEY", file: nil, file_exists: nil }
      end

      def key_from_env_file(age_key_file)
        file_path = File.expand_path(age_key_file)
        { source: "SOPS_AGE_KEY_FILE", file: file_path, file_exists: file_accessible?(file_path) }
      end

      def key_from_default_location
        default_path = File.expand_path("~/.config/sops/age/keys.txt")
        return { source: "default_location", file: default_path, file_exists: true } if file_accessible?(default_path)

        { source: "none", file: nil, file_exists: nil }
      end

      def file_accessible?(path)
        File.exist?(path) && File.readable?(path)
      end

      # Get SOPS version information.
      #
      # @return [String, nil] SOPS version string or nil if unavailable
      #
      def sops_version_info
        return nil unless Binary.available?

        Binary.version
      rescue SopsNotFoundError
        nil
      end

      # Check if age binary is available.
      #
      # @return [Boolean] true if age binary is found
      #
      def age_available?
        require "open3"
        stdout, _stderr, status = Open3.capture3("which", "age")
        status.success? && !stdout.strip.empty?
      end

      # Build the complete info hash from key info and config.
      #
      # @param key_info [Hash] Key source information
      # @param config [Configuration] The configuration instance
      # @return [Hash] Complete debug info hash
      #
      def build_info_hash(key_info, config)
        {
          key_source: key_info[:source], key_file: key_info[:file], key_file_exists: key_info[:file_exists],
          sops_version: sops_version_info, age_available: age_available?,
          config: { encrypted_path: config.encrypted_path, credential_files: config.credential_files,
                    debug_mode: config.debug_mode },
          credential_files: credential_files_info(config)
        }
      end

      # Get information about credential files being checked.
      #
      # @param config [Configuration] The configuration instance
      # @return [Array<Hash>] Array of file information hashes
      #
      def credential_files_info(config)
        config.credential_files.map { |file| build_file_info(config.encrypted_path, file) }
      end

      def build_file_info(encrypted_path, file)
        file_path = File.join(encrypted_path, file)
        { pattern: file, full_path: file_path, exists: File.exist?(file_path), readable: file_accessible?(file_path) }
      end
    end
  end
end
