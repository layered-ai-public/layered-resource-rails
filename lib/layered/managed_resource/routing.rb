require "concurrent/map"

module Layered
  module ManagedResource
    module Routing
      @registry = Concurrent::Map.new

      class << self
        def register(route_key, model_class_name, actions: [], routes: nil)
          @registry[route_key.to_s] = { model: model_class_name.to_s, actions: actions, routes: routes }
        end

        def clear!
          @registry = Concurrent::Map.new
        end

        def lookup(route_key)
          @registry.fetch(route_key.to_s, {})[:model]
        end

        def lookup_actions(route_key)
          @registry.fetch(route_key.to_s, {})[:actions] || []
        end

        def lookup_routes(route_key)
          @registry.fetch(route_key.to_s, {})[:routes]
        end
      end

      MANAGED_ACTIONS = %i[index new create edit update destroy].freeze

      def l_managed_resources(resource_name, model: nil, only: MANAGED_ACTIONS, **options)
        model_class_name = model || begin
          base = resource_name.to_s.classify
          engine_module = if @set != Rails.application.routes
                           @scope[:module]
                         end
          engine_module ? "#{engine_module.to_s.camelize}::#{base}" : base
        end
        route_key = resource_name.to_s
        singular_key = resource_name.to_s.singularize

        prefix = @scope[:path].to_s.delete_prefix("/").tr("/", "_").gsub(/[^a-zA-Z0-9_]/, "_").squeeze("_").presence
        scoped_key = [prefix, route_key].compact.join("_")
        scoped_singular = [prefix, singular_key].compact.join("_")

        # Use a leading "/" when inside a module scope (e.g. another engine) so
        # Rails' add_controller_module treats the path as absolute and skips
        # prepending the engine's namespace. Without a module scope the plain
        # path is used directly.
        controller = if @scope[:module]
                       "/layered/managed_resource/resources"
                     else
                       "layered/managed_resource/resources"
                     end
        actions = Array(only).map(&:to_sym)

        if (actions & %i[new create]).any? && !actions.include?(:index)
          raise ArgumentError,
                "l_managed_resources :#{resource_name} includes :new or :create without :index. " \
                "The form actions require a collection route; add :index to only:."
        end

        if actions.include?(:new) && !actions.include?(:create)
          raise ArgumentError,
                "l_managed_resources :#{resource_name} includes :new without :create. " \
                "The new form posts to the collection route; add :create to only:."
        end

        if actions.include?(:edit) && !actions.include?(:update)
          raise ArgumentError,
                "l_managed_resources :#{resource_name} includes :edit without :update. " \
                "The edit form patches the member route; add :update to only:."
        end

        if actions.include?(:destroy) && !actions.include?(:index)
          raise ArgumentError,
                "l_managed_resources :#{resource_name} includes :destroy without :index. " \
                "Destroy redirects to the collection route; add :index to only:."
        end

        Layered::ManagedResource::Routing.register(scoped_key, model_class_name, actions: actions, routes: @set)

        route_defaults = (options[:defaults] || {}).merge(
          _managed_route_key: scoped_key
        )
        options = options.except(:defaults)

        if actions.include?(:index)
          get route_key, to: "#{controller}#index",
                         as: :"managed_#{scoped_key}",
                         defaults: route_defaults, **options
        end

        if actions.include?(:new)
          get "#{route_key}/new", to: "#{controller}#new",
                                 as: :"new_managed_#{scoped_singular}",
                                 defaults: route_defaults, **options
        end

        if actions.include?(:create)
          post route_key, to: "#{controller}#create",
                          as: nil,
                          defaults: route_defaults, **options
        end

        if actions.include?(:edit)
          get "#{route_key}/:id/edit", to: "#{controller}#edit",
                                       as: :"edit_managed_#{scoped_singular}",
                                       defaults: route_defaults, **options
        end

        member_named = false
        if actions.include?(:update)
          patch "#{route_key}/:id", to: "#{controller}#update",
                                    as: :"managed_#{scoped_singular}",
                                    defaults: route_defaults, **options
          member_named = true
        end

        if actions.include?(:destroy)
          destroy_opts = { to: "#{controller}#destroy", defaults: route_defaults, **options }
          destroy_opts[:as] = :"managed_#{scoped_singular}" unless member_named
          delete "#{route_key}/:id", **destroy_opts
        end
      end
    end
  end
end
