require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.action_controller.include_all_helpers = false
    config.autoload_lib(ignore: %w[assets tasks])
  end
end
