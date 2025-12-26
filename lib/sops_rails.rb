# frozen_string_literal: true

require "singleton"

require_relative "sops_rails/version"
require_relative "sops_rails/errors"
require_relative "sops_rails/configuration"
require_relative "sops_rails/binary"
require_relative "sops_rails/credentials"

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
  # Mutex for thread-safe singleton initialization
  @mutex = Mutex.new

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
    @mutex.synchronize do
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
    @mutex.synchronize do
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
    @mutex.synchronize do
      @config = nil
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
    # The `config` method acquires @mutex internally, so calling it inside
    # another @mutex.synchronize block would cause a recursive lock.
    # This is safe because config is itself thread-safe.
    current_config = config
    @mutex.synchronize do
      @credentials ||= Credentials.load(current_config)
    end
  end
end
