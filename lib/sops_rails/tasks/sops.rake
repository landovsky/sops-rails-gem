# frozen_string_literal: true

require "sops_rails/init"

namespace :sops do
  desc "Initialize sops-rails in this project (set NON_INTERACTIVE=1 to skip prompts)"
  task :init do
    non_interactive = ENV["NON_INTERACTIVE"] == "1"
    SopsRails::Init.run(non_interactive: non_interactive)
  end
end
