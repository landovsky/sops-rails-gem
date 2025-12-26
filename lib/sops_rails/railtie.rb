# frozen_string_literal: true

module SopsRails
  # Rails integration for sops_rails gem.
  #
  # This Railtie ensures that sops_rails is properly loaded when used in a
  # Rails application. It enables automatic gem initialization and makes
  # {SopsRails.credentials} available throughout the Rails application,
  # including in initializers, models, and ERB templates like `database.yml`.
  #
  # Rails automatically loads all files in `config/initializers/`, so if a
  # user creates `config/initializers/sops.rb`, it will be loaded and can use
  # {SopsRails.configure} to customize settings.
  #
  # @example Configuration in initializer
  #   # config/initializers/sops.rb
  #   SopsRails.configure do |config|
  #     config.encrypted_path = "secrets"
  #     config.credential_files = ["credentials.yaml.enc"]
  #   end
  #
  # @example Usage in database.yml
  #   production:
  #     password: <%= SopsRails.credentials.database.password %>
  #
  class Railtie < Rails::Railtie
    # Load rake tasks when Rails is available
    rake_tasks do
      Dir.glob(File.join(__dir__, "../tasks/**/*.rake")).each { |r| load r }
    end
  end
end
