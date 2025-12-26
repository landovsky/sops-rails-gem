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

    # @!attribute [r] age_key_file
    #   @return [String, nil] Path to age private key file.
    #     Read from `SOPS_AGE_KEY_FILE` environment variable.
    attr_reader :age_key_file

    # @!attribute [r] age_key
    #   @return [String, nil] Age private key value.
    #     Read from `SOPS_AGE_KEY` environment variable.
    attr_reader :age_key

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
      @age_key_file = ENV["SOPS_AGE_KEY_FILE"]
      @age_key = ENV["SOPS_AGE_KEY"]
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
  end
end
