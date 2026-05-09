module CustomNamespace
  # Stand-in for an engine's own ApplicationController. Sets a flag so tests
  # can prove `CustomNamespace::ResourcesController` is actually inheriting
  # from this (and not silently bypassed by the gem's default).
  class ApplicationController < ::ApplicationController
    before_action :mark_custom_namespace_application_controller

    private

    def mark_custom_namespace_application_controller
      response.set_header("X-Custom-Namespace-App-Controller", "1")
    end
  end
end
