# frozen_string_literal: true

require "singleton"

require_relative "sops_rails/version"
require_relative "sops_rails/errors"
require_relative "sops_rails/configuration"
require_relative "sops_rails/binary"
require_relative "sops_rails/credentials"
require_relative "sops_rails/debug"
require_relative "sops_rails/railtie" if defined?(Rails)

# SopsRails provides SOPS encryption support for Rails applications.
#
# This gem enables teams to manage encrypted credentials with visible YAML
# structure and individual age keys per developer, integrating Mozilla SOPS
# with Rails.
#
# @example Configure the gem
#   SopsRails.configure do |config|
#     config.encrypted_path = "config"
#     config.credential_files = ["credentials.yaml.enc"]
#   end
#
# @example Access configuration
#   SopsRails.config.encrypted_path
#
module SopsRails
  # Mutexes for thread-safe singleton initialization
  # Using separate mutexes to avoid deadlock when Debug.log calls config from within credentials
  @config_mutex = Mutex.new
  @credentials_mutex = Mutex.new

  # Configure sops_rails settings using a block.
  #
  # @yield [config] Yields the configuration object for setting options
  # @yieldparam config [Configuration] The configuration instance
  # @return [Configuration] Returns the configuration instance
  #
  # @example
  #   SopsRails.configure do |config|
  #     config.encrypted_path = "secrets"
  #     config.credential_files = ["credentials.yaml.enc"]
  #   end
  #
  def self.configure(&block)
    @config_mutex.synchronize do
      @config ||= Configuration.new
    end
    @config.update(&block) if block
    @config
  end

  # Get the current configuration instance.
  #
  # Returns a thread-safe singleton configuration object. If configuration
  # has not been set, returns a new instance with default values.
  #
  # @return [Configuration] The current configuration instance
  #
  # @example
  #   SopsRails.config.encrypted_path # => "config"
  #   SopsRails.config.credential_files # => ["credentials.yaml.enc"]
  #
  def self.config
    @config_mutex.synchronize do
      @config ||= Configuration.new
    end
  end

  # Reset configuration to nil. Primarily used for testing.
  #
  # @return [void]
  #
  # @example
  #   SopsRails.reset!
  #   SopsRails.config # => new Configuration with defaults
  #
  def self.reset!
    @config_mutex.synchronize do
      @config = nil
    end
    @credentials_mutex.synchronize do
      @credentials = nil
    end
  end

  # Access credentials loaded from SOPS-encrypted files.
  #
  # Credentials are lazily loaded on first access and provide OpenStruct-like
  # method chaining for nested access. Missing keys return `nil` instead of
  # raising errors.
  #
  # @return [Credentials] The credentials object
  # @raise [SopsNotFoundError] if SOPS binary is not available (on first access)
  # @raise [DecryptionError] if decryption fails (on first access)
  #
  # @example Method chaining
  #   SopsRails.credentials.aws.access_key_id
  #
  # @example Using dig
  #   SopsRails.credentials.dig(:aws, :access_key_id)
  #
  # @example Missing keys return nil
  #   SopsRails.credentials.nonexistent.nested.key # => nil
  #
  def self.credentials
    # Get config outside the credentials mutex to avoid deadlock.
    # Using separate mutexes allows Debug.log to safely call config
    # from within Credentials.load.
    current_config = config
    @credentials_mutex.synchronize do
      @credentials ||= Credentials.load(current_config)
    end
  end

  # Check if debug mode is currently enabled.
  #
  # @return [Boolean] true if debug mode is enabled
  #
  # @example
  #   SopsRails.debug_mode? # => false
  #   ENV['SOPS_RAILS_DEBUG'] = '1'
  #   SopsRails.reset!
  #   SopsRails.debug_mode? # => true
  #
  def self.debug_mode?
    config.debug_mode
  end

  # Get structured debug information about the current configuration.
  #
  # Returns a hash containing key source information, configuration values,
  # binary availability, and file status. Never includes secret values.
  #
  # @return [Hash] Debug information hash with symbol keys
  #
  # @example
  #   SopsRails.debug_info
  #   # => {
  #   #   key_source: "SOPS_AGE_KEY_FILE",
  #   #   key_file: "/path/to/key.txt",
  #   #   key_file_exists: true,
  #   #   sops_version: "3.8.1",
  #   #   age_available: true,
  #   #   config: { ... },
  #   #   credential_files: [...]
  #   # }
  #
  def self.debug_info
    Debug.info
  end
end
