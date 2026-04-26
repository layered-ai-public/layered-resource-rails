module Layered
  module Resource
    class Engine < ::Rails::Engine
      isolate_namespace Layered::Resource

      initializer "layered-resource-rails.autoload", before: :set_autoload_paths do |app|
        app.config.autoload_paths += [Rails.root.join("app/layered_resources").to_s]
      end

      initializer "layered-resource-rails.routing", before: :add_routing_paths do
        ActionDispatch::Routing::Mapper.include(Layered::Resource::Routing)
      end

      initializer "layered-resource-rails.pagy" do
        if defined?(Pagy)
          ActiveSupport.on_load(:action_controller) do
            include Pagy::Method
          end
        end
      end

      initializer "layered-resource-rails.view_paths" do
        ActiveSupport.on_load(:action_controller) do
          prepend_view_path Engine.root.join("app/views")
        end
      end
    end
  end
end
