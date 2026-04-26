require "concurrent/map"

module Layered
  module Resource
    module Routing
      @registry = Concurrent::Map.new

      class << self
        def register(route_key, resource_class_name, actions: [], routes: nil, parent_params: [], parent_collection_keys: {})
          @registry[route_key.to_s] = {
            resource: resource_class_name.to_s,
            actions: actions,
            routes: routes,
            parent_params: parent_params,
            parent_collection_keys: parent_collection_keys
          }
        end

        def clear!
          @registry = Concurrent::Map.new
        end

        def lookup(route_key)
          @registry.fetch(route_key.to_s, nil)
        end
      end

      RESOURCE_ACTIONS = %i[index show new create edit update destroy].freeze

      def layered_resources(resource_name, resource: nil, controller: nil, only: RESOURCE_ACTIONS, **options)
        resource_class_name = resource || "#{resource_name.to_s.classify}Resource"
        route_key = resource_name.to_s
        singular_key = resource_name.to_s.singularize

        raw_scope_path = @scope[:path].to_s
        parent_params = raw_scope_path.scan(/:([a-zA-Z_]\w*)/).flatten.map(&:to_sym)

        # For each parent param, compute the route key its collection
        # would have been registered under. e.g. in scope
        # "orgs/:org_id/users/:user_id", :user_id maps to "orgs_users".
        segments = raw_scope_path.split("/")
        parent_collection_keys = {}
        segments.each_with_index do |seg, i|
          next unless seg.start_with?(":")
          param = seg.delete_prefix(":").to_sym
          next if i == 0

          resource_seg = segments[i - 1]
          scope_before = segments[0...[i - 1, 0].max].join("/")
          static_before = scope_before.gsub(%r{/?:[a-zA-Z_]\w*}, "")
          pfx = static_before.delete_prefix("/").tr("/", "_").gsub(/[^a-zA-Z0-9_]/, "_").squeeze("_").presence
          parent_collection_keys[param] = [pfx, resource_seg].compact.join("_")
        end

        static_path = raw_scope_path.gsub(%r{/?:[a-zA-Z_]\w*}, "")
        prefix = static_path.delete_prefix("/").tr("/", "_").gsub(/[^a-zA-Z0-9_]/, "_").squeeze("_").presence
        scoped_key = [prefix, route_key].compact.join("_")
        scoped_singular = [prefix, singular_key].compact.join("_")

        # Use a leading "/" when inside a module scope (e.g. another engine) so
        # Rails' add_controller_module treats the path as absolute and skips
        # prepending the engine's namespace. Without a module scope the plain
        # path is used directly. The caller can override with controller: to
        # route to a custom subclass of Layered::Resource::ResourcesController.
        controller = if controller
                       controller.to_s
                     elsif @scope[:module]
                       "/layered/resource/resources"
                     else
                       "layered/resource/resources"
                     end
        actions = Array(only).map(&:to_sym)

        if (actions & %i[new create]).any? && !actions.include?(:index)
          raise ArgumentError,
                "layered_resources :#{resource_name} includes :new or :create without :index. " \
                "The form actions require a collection route; add :index to only:."
        end

        if actions.include?(:new) && !actions.include?(:create)
          raise ArgumentError,
                "layered_resources :#{resource_name} includes :new without :create. " \
                "The new form posts to the collection route; add :create to only:."
        end

        if actions.include?(:edit) && !actions.include?(:update)
          raise ArgumentError,
                "layered_resources :#{resource_name} includes :edit without :update. " \
                "The edit form patches the member route; add :update to only:."
        end

        if actions.include?(:update) && !actions.include?(:index)
          raise ArgumentError,
                "layered_resources :#{resource_name} includes :update without :index. " \
                "Update redirects to the collection route; add :index to only:."
        end

        if actions.include?(:destroy) && !actions.include?(:index)
          raise ArgumentError,
                "layered_resources :#{resource_name} includes :destroy without :index. " \
                "Destroy redirects to the collection route; add :index to only:."
        end

        Layered::Resource::Routing.register(scoped_key, resource_class_name, actions: actions, routes: @set, parent_params: parent_params, parent_collection_keys: parent_collection_keys)

        route_defaults = (options[:defaults] || {}).merge(
          _layered_resource_route_key: scoped_key
        )
        options = options.except(:defaults)

        if actions.include?(:index)
          get route_key, to: "#{controller}#index",
                         as: :"layered_#{scoped_key}",
                         defaults: route_defaults, **options
        end

        if actions.include?(:new)
          get "#{route_key}/new", to: "#{controller}#new",
                                 as: :"new_layered_#{scoped_singular}",
                                 defaults: route_defaults, **options
        end

        if actions.include?(:create)
          post route_key, to: "#{controller}#create",
                          as: nil,
                          defaults: route_defaults, **options
        end

        if actions.include?(:edit)
          get "#{route_key}/:id/edit", to: "#{controller}#edit",
                                       as: :"edit_layered_#{scoped_singular}",
                                       defaults: route_defaults, **options
        end

        member_named = false
        if actions.include?(:show)
          get "#{route_key}/:id", to: "#{controller}#show",
                                  as: :"layered_#{scoped_singular}",
                                  defaults: route_defaults, **options
          member_named = true
        end

        if actions.include?(:update)
          update_opts = { to: "#{controller}#update", defaults: route_defaults, **options }
          update_opts[:as] = member_named ? nil : :"layered_#{scoped_singular}"
          patch "#{route_key}/:id", **update_opts
          member_named = true
        end

        if actions.include?(:destroy)
          destroy_opts = { to: "#{controller}#destroy", defaults: route_defaults, **options }
          destroy_opts[:as] = member_named ? nil : :"layered_#{scoped_singular}"
          delete "#{route_key}/:id", **destroy_opts
        end
      end
    end
  end
end
