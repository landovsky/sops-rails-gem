# frozen_string_literal: true

require "yaml"

module SopsRails
  # Provides OpenStruct-like access to SOPS-encrypted credentials.
  #
  # Supports method chaining for nested access (`credentials.aws.access_key_id`),
  # the `dig` method for safe traversal, and returns `nil` for missing keys
  # instead of raising errors.
  #
  # Credentials are lazily loaded from the encrypted file on first access.
  #
  # @example Method chaining
  #   SopsRails.credentials.aws.access_key_id # => "AKIAIOSFODNN7EXAMPLE"
  #
  # @example Using dig
  #   SopsRails.credentials.dig(:aws, :access_key_id) # => "AKIAIOSFODNN7EXAMPLE"
  #
  # @example Missing keys return nil
  #   SopsRails.credentials.nonexistent.nested.key # => nil
  #
  class Credentials
    # Initialize a new Credentials instance.
    #
    # @param data [Hash] The credentials data hash (typically from parsed YAML)
    #
    # @example
    #   creds = SopsRails::Credentials.new(aws: { key: "secret" })
    #   creds.aws.key # => "secret"
    #
    def initialize(data = {})
      @data = deep_symbolize_keys(data || {})
    end

    # Access a credential value by key using method syntax.
    #
    # Returns a nested Credentials object for nested hashes, or the value
    # directly for leaf values. Returns {NullCredentials} for missing keys
    # to allow chained access without raising errors.
    #
    # @param method_name [Symbol] The key to access
    # @return [Credentials, NullCredentials, Object] The value at the key
    #
    # @example
    #   credentials.aws.access_key_id
    #
    def method_missing(method_name, *)
      key = method_name.to_sym
      value = @data[key]
      wrap_value(value)
    end

    # Check if a method would be handled by method_missing.
    #
    # All method calls are handled (missing keys return NullCredentials).
    #
    # @return [Boolean] Always returns true
    #
    def respond_to_missing?(*)
      true
    end

    # Safely dig into nested credentials.
    #
    # Works like `Hash#dig` but returns `nil` for missing keys at any level.
    #
    # @param keys [Array<Symbol, String>] The keys to traverse
    # @return [Object, nil] The value at the nested path, or nil if not found
    #
    # @example
    #   credentials.dig(:aws, :access_key_id) # => "AKIAIOSFODNN7EXAMPLE"
    #   credentials.dig(:missing, :key) # => nil
    #
    def dig(*keys)
      keys = keys.map(&:to_sym)
      @data.dig(*keys)
    end

    # Access a credential value using bracket syntax.
    #
    # @param key [Symbol, String] The key to access
    # @return [Credentials, NullCredentials, Object] The value at the key
    #
    # @example
    #   credentials[:aws][:access_key_id]
    #
    def [](key)
      value = @data[key.to_sym]
      wrap_value(value)
    end

    # Return the raw hash representation of credentials.
    #
    # @return [Hash] The credentials as a hash with symbol keys
    #
    # @example
    #   credentials.to_h # => { aws: { key: "secret" } }
    #
    def to_h
      @data.dup
    end

    # Check if credentials are empty.
    #
    # @return [Boolean] true if no credentials are loaded
    #
    def empty?
      @data.empty?
    end

    # Check if a key exists in credentials.
    #
    # @param key [Symbol, String] The key to check
    # @return [Boolean] true if the key exists
    #
    # @example
    #   credentials.key?(:aws) # => true
    #   credentials.key?(:nonexistent) # => false
    #
    def key?(key)
      @data.key?(key.to_sym)
    end
    alias has_key? key?

    # Return all top-level keys in credentials.
    #
    # @return [Array<Symbol>] Array of credential keys
    #
    # @example
    #   credentials.keys # => [:aws, :database]
    #
    def keys
      @data.keys
    end

    # Provide a readable inspection of the credentials.
    #
    # Shows the structure without exposing actual secret values.
    #
    # @return [String] Inspection string
    #
    # @example
    #   credentials.inspect # => "#<SopsRails::Credentials keys=[:aws, :database]>"
    #
    def inspect
      "#<#{self.class.name} keys=#{keys.inspect}>"
    end

    # Load credentials from configured files.
    #
    # Reads the encrypted file specified in configuration, decrypts it using
    # the SOPS binary, parses the YAML, and returns a new Credentials instance.
    #
    # @param config [Configuration] The configuration to use (defaults to SopsRails.config)
    # @return [Credentials] A new Credentials instance with loaded data
    # @raise [SopsNotFoundError] if SOPS binary is not available
    # @raise [DecryptionError] if decryption fails
    #
    # @example
    #   creds = SopsRails::Credentials.load
    #   creds.aws.access_key_id
    #
    def self.load(config = SopsRails.config)
      data = {}

      config.credential_files.each do |file|
        file_path = File.join(config.encrypted_path, file)
        next unless File.exist?(file_path)

        decrypted_content = Binary.decrypt(file_path)
        file_data = YAML.safe_load(decrypted_content, permitted_classes: [], permitted_symbols: [],
                                                      aliases: true) || {}
        data = deep_merge(data, file_data)
      end

      new(data)
    end

    private

    # Wrap a value in appropriate type for method chaining.
    #
    # @param value [Object] The value to wrap
    # @return [Credentials, NullCredentials, Object] Wrapped value
    #
    def wrap_value(value)
      case value
      when Hash
        Credentials.new(value)
      when nil
        NullCredentials.instance
      else
        value
      end
    end

    # Deep symbolize all keys in a hash.
    #
    # @param hash [Hash] The hash to transform
    # @return [Hash] Hash with all keys converted to symbols
    #
    def deep_symbolize_keys(hash)
      return hash unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(key, value), result|
        sym_key = key.to_sym
        result[sym_key] = value.is_a?(Hash) ? deep_symbolize_keys(value) : value
      end
    end

    class << self
      private

      # Deep merge two hashes.
      #
      # @param base [Hash] The base hash
      # @param override [Hash] The hash to merge in (values override base)
      # @return [Hash] Merged hash
      #
      def deep_merge(base, override)
        base.merge(override) do |_key, old_val, new_val|
          if old_val.is_a?(Hash) && new_val.is_a?(Hash)
            deep_merge(old_val, new_val)
          else
            new_val
          end
        end
      end
    end
  end

  # Null object pattern for missing credential keys.
  #
  # Returns itself for method calls to allow safe chaining like
  # `credentials.missing.nested.key` without raising NoMethodError.
  # Evaluates to `nil` in boolean contexts and comparisons.
  #
  # @example
  #   null = SopsRails::NullCredentials.instance
  #   null.anything.you.want.nil? # => true
  #   null.anything.you.want == nil # => true
  #
  class NullCredentials
    include Singleton

    # Returns self for any method call to allow chaining.
    #
    # @return [NullCredentials] Returns self for chaining
    #
    def method_missing(*)
      self
    end

    # All methods are handled.
    #
    # @return [Boolean] Always true
    #
    def respond_to_missing?(*)
      true
    end

    # Returns self for bracket access to allow chaining.
    #
    # @return [NullCredentials] Returns self for chaining
    #
    def [](*)
      self
    end

    # Returns nil for dig (final value).
    #
    # @return [nil] Always returns nil
    #
    def dig(*)
      nil
    end

    # Returns true to indicate this is a nil-like object.
    #
    # @return [Boolean] Always true
    #
    def nil?
      true
    end

    # Compare equal to nil.
    #
    # @param other [Object] The object to compare with
    # @return [Boolean] True if other is nil or NullCredentials
    #
    def ==(other)
      other.nil? || other.is_a?(NullCredentials)
    end

    # Convert to string as empty string.
    #
    # @return [String] Empty string
    #
    def to_s
      ""
    end

    # Inspect representation.
    #
    # @return [String] Inspection string
    #
    def inspect
      "nil"
    end
  end
end
