# frozen_string_literal: true

module SopsValidationHelper
  module_function

  def valid_sops_file?(path)
    return false unless File.exist?(path)

    content = File.read(path)
    parsed = YAML.safe_load(content, permitted_classes: [Time])
    parsed.is_a?(Hash) && parsed.key?("sops") && parsed["sops"].is_a?(Hash)
  rescue Psych::SyntaxError, Errno::ENOENT
    false
  end

  def can_decrypt_with_sops?(path)
    return false unless SopsRails::Binary.available?

    SopsRails::Binary.decrypt(path)
    true
  rescue SopsRails::DecryptionError
    false
  end

  def integration_test_prerequisites_met?
    return false unless SopsRails::Binary.available?
    return false unless age_binary_available?
    return false unless age_key_file_exists?

    true
  end

  def age_binary_available?
    stdout, _, status = Open3.capture3("which", "age")
    status.success? && !stdout.strip.empty?
  end

  def age_key_file_exists?
    File.exist?(SopsRails.config.default_age_key_path)
  end

  def sops_config_exists?
    File.exist?(".sops.yaml")
  end
end
