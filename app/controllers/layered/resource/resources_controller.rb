module Layered
  module Resource
    # Default controller for `layered_resources` routes — inherits from the
    # host app's ApplicationController so before_actions like Devise's
    # `authenticate_user!` apply automatically. For an engine that needs
    # the engine's own ApplicationController (and its authorize block),
    # define a sibling controller and include the concern:
    #
    #   class Layered::Assistant::ResourcesController < Layered::Assistant::ApplicationController
    #     include Layered::Resource::Controller
    #   end
    #
    # `layered_resources` routes will auto-detect a namespaced controller
    # by name when a `namespace:` option is given (or inferred from the
    # surrounding routes module scope).
    class ResourcesController < ::ApplicationController
      include Controller
    end
  end
end
