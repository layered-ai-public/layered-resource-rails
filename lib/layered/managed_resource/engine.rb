module Layered
  module ManagedResource
    class Engine < ::Rails::Engine
      isolate_namespace Layered::ManagedResource

      initializer "layered-managed-resource-rails.autoload", before: :set_autoload_paths do |app|
        app.config.autoload_paths += [Rails.root.join("app/managed_resources").to_s]
      end

      initializer "layered-managed-resource-rails.routing", before: :add_routing_paths do
        ActionDispatch::Routing::Mapper.include(Layered::ManagedResource::Routing)
      end

      initializer "layered-managed-resource-rails.pagy" do
        if defined?(Pagy)
          ActiveSupport.on_load(:action_controller) do
            include Pagy::Method
          end
        end
      end

      initializer "layered-managed-resource-rails.view_paths" do
        ActiveSupport.on_load(:action_controller) do
          prepend_view_path Engine.root.join("app/views")
        end
      end
    end
  end
end
