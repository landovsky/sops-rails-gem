# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "sops_rails"
require "sops_rails/init"

# Helper module for sops:show task argument resolution
module SopsShowTask
  class << self
    # Resolve file path from argument or RAILS_ENV
    #
    # Priority order:
    # 1. Explicit file_arg (highest priority)
    # 2. RAILS_ENV environment variable
    # 3. Default credentials file
    #
    # @param file_arg [String, nil] Optional explicit file path
    # @return [String] Resolved file path
    def resolve_file_path(file_arg)
      return file_arg if file_arg && !file_arg.empty?
      return env_credentials_path(ENV["RAILS_ENV"]) if ENV["RAILS_ENV"]

      default_credentials_path
    end

    private

    def env_credentials_path(environment)
      File.join(SopsRails.config.encrypted_path, "credentials.#{environment}.yaml.enc")
    end

    def default_credentials_path
      config = SopsRails.config
      File.join(config.encrypted_path, config.credential_files.first)
    end
  end
end

# Helper module for sops:edit task argument resolution
module SopsEditTask
  # Default template mimics Rails credentials with secret_key_base.
  # Note: secret_key_base is generated fresh each time the template is used.
  def self.credentials_template
    <<~YAML
      # Used as the base secret for all MessageVerifiers in Rails, including the one protecting cookies.
      secret_key_base: #{SecureRandom.hex(64)}

      # Add your application secrets here:
      # aws:
      #   access_key_id: your_access_key
      #   secret_access_key: your_secret_key
      #
      # database:
      #   password: your_db_password
    YAML
  end

  class << self
    # Resolve file path from argument or RAILS_ENV
    #
    # Priority order:
    # 1. Explicit file_arg (highest priority)
    # 2. RAILS_ENV environment variable
    # 3. Default credentials file
    #
    # @param file_arg [String, nil] Optional explicit file path
    # @return [String] Resolved file path
    def resolve_file_path(file_arg)
      return file_arg if file_arg && !file_arg.empty?
      return env_credentials_path(ENV["RAILS_ENV"]) if ENV["RAILS_ENV"]

      default_credentials_path
    end

    # Create initial encrypted file with Rails-like template.
    # Returns true if file was created, false if it already existed.
    #
    # @param file_path [String] Path to create the encrypted file
    # @return [Boolean] true if file was created, false if it already exists
    def ensure_template_exists(file_path) # rubocop:disable Naming/PredicateMethod
      return false if File.exist?(file_path)

      puts "Creating new credentials file: #{file_path}"
      SopsRails::Binary.encrypt_to_file(file_path, credentials_template)
      true
    end

    private

    def env_credentials_path(environment)
      File.join(SopsRails.config.encrypted_path, "credentials.#{environment}.yaml.enc")
    end

    def default_credentials_path
      config = SopsRails.config
      File.join(config.encrypted_path, config.credential_files.first)
    end
  end
end

namespace :sops do
  desc "Initialize sops-rails in this project (set NON_INTERACTIVE=1 to skip prompts)"
  task :init do
    non_interactive = ENV["NON_INTERACTIVE"] == "1"
    SopsRails::Init.run(non_interactive: non_interactive)
  end

  desc "Display decrypted credentials (usage: sops:show[FILE] or RAILS_ENV=production sops:show)"
  task :show, [:file_path] do |_t, args|
    file_path = SopsShowTask.resolve_file_path(args[:file_path])

    unless File.exist?(file_path)
      warn "Error: File not found: #{file_path}"
      exit 1
    end

    decrypted_content = SopsRails::Binary.decrypt(file_path)
    $stdout.print decrypted_content
  rescue SopsRails::SopsNotFoundError, SopsRails::DecryptionError => e
    warn "Error: #{e.message}"
    exit 1
  end

  desc "Edit encrypted credentials (usage: sops:edit[FILE] or RAILS_ENV=production sops:edit)"
  task :edit, [:file_path] do |_t, args|
    file_path = SopsEditTask.resolve_file_path(args[:file_path])

    # Create parent directory if it doesn't exist
    file_dir = File.dirname(file_path)
    FileUtils.mkdir_p(file_dir) unless File.directory?(file_dir)

    # Create template if file doesn't exist (mimics Rails credentials behavior)
    SopsEditTask.ensure_template_exists(file_path)

    # Open file in SOPS editor
    success = SopsRails::Binary.edit(file_path)
    exit 1 unless success
  rescue SopsRails::SopsNotFoundError, SopsRails::EncryptionError => e
    warn "Error: #{e.message}"
    exit 1
  end
end
