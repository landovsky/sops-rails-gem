# frozen_string_literal: true

module SopsRails
  # Configuration class for sops_rails gem settings.
  #
  # Provides thread-safe singleton configuration accessible via
  # {SopsRails.config}. Configuration can be set using the
  # {SopsRails.configure} block method.
  #
  # @example Basic usage
  #   SopsRails.configure do |config|
  #     config.encrypted_path = "secrets"
  #     config.credential_files = ["credentials.yaml.enc", "secrets.yaml.enc"]
  #   end
  #
  # @example Accessing configuration
  #   SopsRails.config.encrypted_path # => "secrets"
  #   SopsRails.config.credential_files # => ["credentials.yaml.enc", "secrets.yaml.enc"]
  #
  class Configuration
    # @!attribute [rw] encrypted_path
    #   @return [String] Path to directory containing encrypted credential files.
    #     Default: `"config"`
    attr_accessor :encrypted_path

    # @!attribute [rw] credential_files
    #   @return [Array<String>] Array of credential file patterns to load.
    #     Default: `["credentials.yaml.enc"]`
    attr_accessor :credential_files

    # @!attribute [rw] debug_mode
    #   @return [Boolean] Whether debug mode is enabled.
    #     Default: `false` or value from `SOPS_RAILS_DEBUG` environment variable.
    attr_accessor :debug_mode

    # @!attribute [r] age_key_file
    #   @return [String, nil] Path to age private key file.
    #     Read from `SOPS_AGE_KEY_FILE` environment variable.
    attr_reader :age_key_file

    # @!attribute [r] age_key
    #   @return [String, nil] Age private key value.
    #     Read from `SOPS_AGE_KEY` environment variable.
    attr_reader :age_key

    # Default age key file path for Linux/XDG systems.
    DEFAULT_AGE_KEY_PATH_XDG = "~/.config/sops/age/keys.txt"

    # Default age key file path for macOS.
    DEFAULT_AGE_KEY_PATH_MACOS = "~/Library/Application Support/sops/age/keys.txt"

    # Initialize a new Configuration instance with default values.
    #
    # Reads environment variables `SOPS_AGE_KEY_FILE` and `SOPS_AGE_KEY`
    # for age key configuration.
    #
    # @example
    #   config = SopsRails::Configuration.new
    #   config.encrypted_path # => "config"
    #
    def initialize
      @encrypted_path = "config"
      @credential_files = ["credentials.yaml.enc"]
      @age_key_file = presence(ENV.fetch("SOPS_AGE_KEY_FILE", nil))
      @age_key = presence(ENV.fetch("SOPS_AGE_KEY", nil))
      debug_env = ENV.fetch("SOPS_RAILS_DEBUG", "")
      @debug_mode = !debug_env.empty? && debug_env != "0" && debug_env.downcase != "false"
      @mutex = Mutex.new
    end

    # Thread-safe method to update configuration.
    #
    # @yield [self] Yields self for block-style configuration
    # @return [self] Returns self for method chaining
    #
    # @example
    #   config.update do |c|
    #     c.encrypted_path = "custom"
    #   end
    #
    def update(&block)
      @mutex.synchronize do
        block&.call(self)
      end
      self
    end

    # Resolve the age key file path to use for decryption.
    #
    # Priority order:
    # 1. SOPS_AGE_KEY environment variable (inline key, no file needed)
    # 2. SOPS_AGE_KEY_FILE environment variable (if file exists)
    # 3. OS-specific default location (if file exists)
    # 4. nil (SOPS will use .sops.yaml rules or fail)
    #
    # @return [String, nil] Resolved path to age key file, or nil
    #
    # @example
    #   config.resolved_age_key_file
    #   # => "/Users/me/.config/sops/age/keys.txt"
    #
    def resolved_age_key_file
      # If SOPS_AGE_KEY is set, no file is needed
      return nil if @age_key

      # Check explicit SOPS_AGE_KEY_FILE first
      if @age_key_file
        expanded = File.expand_path(@age_key_file)
        return expanded if File.exist?(expanded)
      end

      # Fall back to OS-specific default
      default = default_age_key_path
      return default if File.exist?(default)

      nil
    end

    # Get the OS-specific default path for age keys.
    #
    # @return [String] Expanded path to default age key location
    #
    def default_age_key_path
      path = macos? ? DEFAULT_AGE_KEY_PATH_MACOS : DEFAULT_AGE_KEY_PATH_XDG
      File.expand_path(path)
    end

    # Check if running on macOS.
    #
    # @return [Boolean] true if on macOS/Darwin
    #
    def macos?
      RUBY_PLATFORM.include?("darwin")
    end

    # Extract the public key from the resolved age key file.
    #
    # Reads the key file and extracts the public key from the comment line
    # that age-keygen adds (format: "# public key: age1...").
    #
    # @return [String, nil] The public key, or nil if not found
    #
    def public_key
      key_file = resolved_age_key_file
      return nil unless key_file && File.exist?(key_file)

      extract_public_key_from_file(key_file)
    end

    private

    # Convert empty strings to nil, preserving nil and non-empty strings.
    #
    # @param value [String, nil] The value to check
    # @return [String, nil] The original value if non-empty, nil otherwise
    #
    def presence(value)
      return nil if value.nil? || value.empty?

      value
    end

    # Extract public key from an age key file.
    #
    # @param file_path [String] Path to the age key file
    # @return [String, nil] The public key, or nil if not found
    #
    def extract_public_key_from_file(file_path)
      File.foreach(file_path) do |line|
        match = line.match(/^#\s*public key:\s*(age1\S+)/)
        return match[1] if match
      end
      nil
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end
  end
end
