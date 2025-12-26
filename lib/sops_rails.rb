# frozen_string_literal: true

require_relative "sops_rails/version"
require_relative "sops_rails/errors"
require_relative "sops_rails/configuration"
require_relative "sops_rails/binary"

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
    end
  end
end
