# frozen_string_literal: true

require "sops_rails"
require "sops_rails/init"

# Helper module for sops:show task argument parsing
module SopsShowTask
  ENV_FLAGS = ["-e", "--environment"].freeze

  class << self
    # Parse ARGV for file argument and environment flag
    def parse_args
      task_args = extract_task_args
      parse_task_args(task_args)
    end

    # Resolve file path from arguments
    def resolve_file_path(file_arg, environment)
      return file_arg if file_arg && !file_arg.empty?
      return env_credentials_path(environment) if environment && !environment.empty?

      default_credentials_path
    end

    private

    def extract_task_args
      ARGV.drop_while { |arg| arg != "sops:show" }.drop(1)
    end

    def parse_task_args(task_args)
      env_idx = task_args.index { |arg| ENV_FLAGS.include?(arg) }
      environment = env_idx ? task_args[env_idx + 1] : nil

      # Find first positional argument (not a flag or flag value)
      file_arg = find_positional_arg(task_args, env_idx)

      [file_arg, environment]
    end

    def find_positional_arg(task_args, env_idx)
      task_args.each_with_index do |arg, idx|
        next if arg.start_with?("-")
        next if env_idx && (idx == env_idx + 1) # Skip environment value

        return arg
      end
      nil
    end

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

  desc "Display decrypted credentials (usage: sops:show FILE or sops:show -e ENVIRONMENT)"
  task :show do
    file_arg, environment = SopsShowTask.parse_args
    file_path = SopsShowTask.resolve_file_path(file_arg, environment)

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
end
