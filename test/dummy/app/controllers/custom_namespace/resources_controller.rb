module CustomNamespace
  class ResourcesController < CustomNamespace::ApplicationController
    include Layered::Resource::Controller
  end
end
