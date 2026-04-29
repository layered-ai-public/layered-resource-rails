require "concurrent/map"

module Layered
  module Resource
    module Routing
      @registry = Concurrent::Map.new

      class << self
        def register(route_key, resource_class_name, actions: [], routes: nil, parent_params: [], parent_collection_keys: {}, resource_name: nil, member_actions: [], collection_actions: [])
          @registry[route_key.to_s] = {
            resource: resource_class_name.to_s,
            actions: actions,
            routes: routes,
            parent_params: parent_params,
            parent_collection_keys: parent_collection_keys,
            resource_name: resource_name.to_s,
            member_actions: member_actions,
            collection_actions: collection_actions
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

      # Collects custom member/collection routes declared inside a
      # `layered_resources` block. Mirrors the small subset of Rails'
      # `resources` block DSL we care about: nested `member do ... end` /
      # `collection do ... end` containing HTTP-verb action declarations.
      class CustomActionsBuilder
        VERBS = %i[get post patch put delete].freeze

        attr_reader :member_actions, :collection_actions

        def initialize
          @member_actions = []
          @collection_actions = []
          @scope = nil
        end

        def member(&block)
          previous, @scope = @scope, :member
          instance_eval(&block)
        ensure
          @scope = previous
        end

        def collection(&block)
          previous, @scope = @scope, :collection
          instance_eval(&block)
        ensure
          @scope = previous
        end

        VERBS.each do |verb|
          define_method(verb) do |action_name|
            unless @scope
              raise ArgumentError,
                    "#{verb} :#{action_name} declared outside member/collection block in layered_resources"
            end
            target = @scope == :member ? @member_actions : @collection_actions
            target << { verb: verb, action: action_name.to_sym }
          end
        end

        def method_missing(name, *_args, &_block)
          raise ArgumentError,
                "`#{name}` is not supported inside a layered_resources block. " \
                "Only `member`, `collection`, and HTTP verbs (#{VERBS.join(', ')}) are available; " \
                "declare other routes outside the block."
        end

        def respond_to_missing?(_name, _include_private = false)
          false
        end
      end

      def layered_resources(resource_name, resource: nil, controller: nil, only: RESOURCE_ACTIONS, except: nil, **options, &block)
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

        controller_override = controller
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
        actions -= Array(except).map(&:to_sym) if except

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

        custom_member = []
        custom_collection = []
        if block
          unless controller_override
            raise ArgumentError,
                  "layered_resources :#{resource_name} declared a block of custom actions " \
                  "but no controller: override. Generate one with " \
                  "`rails g layered:resource:controller #{resource_name}` and pass " \
                  "controller: \"#{resource_name}\"."
          end

          builder = CustomActionsBuilder.new
          builder.instance_eval(&block)
          custom_member = builder.member_actions
          custom_collection = builder.collection_actions

          # Path collisions with built-ins: collection :new shares
          # /<route_key>/new, and member :edit shares /<route_key>/:id/edit.
          # Other CRUD names live on different paths (:show is /:id, not
          # /:id/show; :create is POST /<key>, not /<key>/create) so they
          # don't collide. Built-in routes are declared first, so without
          # these guards a custom :edit/:new would silently lose the
          # dispatch race. Only flag when the colliding built-in is
          # actually enabled (respect except:/only:).
          if custom_collection.any? { |a| a[:action] == :new } && actions.include?(:new)
            raise ArgumentError,
                  "layered_resources :#{resource_name} declares collection :new, " \
                  "which collides with the built-in /#{route_key}/new route. " \
                  "Rename it or pass `except: [:new]`."
          end

          if custom_member.any? { |a| a[:action] == :edit } && actions.include?(:edit)
            raise ArgumentError,
                  "layered_resources :#{resource_name} declares member :edit, " \
                  "which collides with the built-in /#{route_key}/:id/edit route. " \
                  "Rename it or pass `except: [:edit]`."
          end
        end

        Layered::Resource::Routing.register(scoped_key, resource_class_name,
                                            actions: actions,
                                            routes: @set,
                                            parent_params: parent_params,
                                            parent_collection_keys: parent_collection_keys,
                                            resource_name: route_key,
                                            member_actions: custom_member.map { |a| a[:action] },
                                            collection_actions: custom_collection.map { |a| a[:action] })

        route_defaults = (options[:defaults] || {}).merge(
          _layered_resource_route_key: scoped_key
        )
        options = options.except(:defaults)

        if actions.include?(:index)
          get route_key, to: "#{controller}#index",
                         as: scoped_key.to_sym,
                         defaults: route_defaults, **options
        end

        if actions.include?(:new)
          get "#{route_key}/new", to: "#{controller}#new",
                                 as: :"new_#{scoped_singular}",
                                 defaults: route_defaults, **options
        end

        if actions.include?(:create)
          post route_key, to: "#{controller}#create",
                          as: nil,
                          defaults: route_defaults, **options
        end

        # Custom collection routes must be declared before member `:id` routes
        # so that paths like `/posts/bulk_archive` don't get shadowed by
        # `/posts/:id` (which would otherwise dispatch to #show with
        # id: "bulk_archive").
        custom_collection.each do |route|
          public_send(route[:verb], "#{route_key}/#{route[:action]}",
                      to: "#{controller}##{route[:action]}",
                      as: :"#{route[:action]}_#{scoped_key}",
                      defaults: route_defaults, **options)
        end

        if actions.include?(:edit)
          get "#{route_key}/:id/edit", to: "#{controller}#edit",
                                       as: :"edit_#{scoped_singular}",
                                       defaults: route_defaults, **options
        end

        member_named = false
        if actions.include?(:show)
          get "#{route_key}/:id", to: "#{controller}#show",
                                  as: scoped_singular.to_sym,
                                  defaults: route_defaults, **options
          member_named = true
        end

        if actions.include?(:update)
          update_opts = { to: "#{controller}#update", defaults: route_defaults, **options }
          update_opts[:as] = member_named ? nil : scoped_singular.to_sym
          patch "#{route_key}/:id", **update_opts
          member_named = true
        end

        if actions.include?(:destroy)
          destroy_opts = { to: "#{controller}#destroy", defaults: route_defaults, **options }
          destroy_opts[:as] = member_named ? nil : scoped_singular.to_sym
          delete "#{route_key}/:id", **destroy_opts
        end

        custom_member.each do |route|
          public_send(route[:verb], "#{route_key}/:id/#{route[:action]}",
                      to: "#{controller}##{route[:action]}",
                      as: :"#{route[:action]}_#{scoped_singular}",
                      defaults: route_defaults, **options)
        end
      end
    end
  end
end
