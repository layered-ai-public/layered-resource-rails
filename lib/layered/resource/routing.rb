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

      def layered_resources(resource_name, resource: nil, controller: nil, namespace: nil, only: RESOURCE_ACTIONS, except: nil, **options, &block)
        # When called inside `resources :foo do ... end` (or `resource :foo do`),
        # Rails has set up a resource_scope but hasn't pushed the parent's
        # path into @scope. Push it ourselves via scope(path:) and recurse.
        # We also null out the inherited @scope[:as] for the recursion so our
        # full as_base (computed from path params, e.g. "user_posts") composes
        # correctly — Rails' :nested scope_level orders `[name_prefix, prefix]`,
        # which would otherwise turn `as: :new_user_post` into `:user_new_user_post`
        # when name_prefix is already "user" from an outer `resources :users do`.
        #
        # Note: this branch leans on Rails-internal Mapper APIs
        # (`with_scope_level`, `@scope[:scope_level_resource]`, `Resource#nested_scope`,
        # direct `@scope.frame[:as]` mutation). Verified against Rails 8.x; if a
        # future Rails release renames or removes any of these, the integration
        # test "layered_resources inside resources :foo do block …" will fail at
        # boot and this block needs revisiting.
        if @scope.resource_scope?
          parent = @scope[:scope_level_resource]
          return send(:with_scope_level, :nested) do
            scope(path: parent.nested_scope) do
              saved_as = @scope.frame[:as]
              @scope.frame[:as] = nil
              begin
                layered_resources(resource_name,
                                  resource: resource, controller: controller, namespace: namespace,
                                  only: only, except: except, **options, &block)
              ensure
                @scope.frame[:as] = saved_as
              end
            end
          end
        end

        # `namespace:` is explicit-only — passing "Layered::Assistant"
        # derives the resource class as `Layered::Assistant::PostResource`
        # and routes to `Layered::Assistant::ResourcesController` (when
        # defined). We don't auto-infer from a surrounding `namespace :foo`
        # block because Rails composes URL-helper names differently there
        # than the gem-shipped views expect; for that pattern, use
        # `scope path: "foo", module: "foo"` and pass `namespace:` here.
        namespace = namespace.to_s.presence

        resource_class_name = resource ||
          (namespace ? "#{namespace}::#{resource_name.to_s.classify}Resource" : "#{resource_name.to_s.classify}Resource")
        route_key = resource_name.to_s
        singular_key = resource_name.to_s.singularize

        raw_scope_path = @scope[:path].to_s
        parent_params = raw_scope_path.scan(/:([a-zA-Z_]\w*)/).flatten.map(&:to_sym)

        # For each parent param, compute the route key its collection would
        # have been registered under (e.g. in scope "orgs/:org_id/users/:user_id",
        # :user_id maps to the registry key "org_users"). Used by breadcrumbs
        # and link: columns to find the parent's resource entry.
        segments = raw_scope_path.split("/")
        parent_collection_keys = {}
        accumulated_param_prefix = []
        segments.each_with_index do |seg, i|
          next unless seg.start_with?(":")
          param = seg.delete_prefix(":").to_sym
          # Rails-standard prefix for a nested resource: each parent param
          # contributes its singularised stem (`:user_id` → "user").
          parent_collection_keys[param] = [*accumulated_param_prefix, segments[i - 1]].compact.join("_") if i > 0
          accumulated_param_prefix << param.to_s.delete_suffix("_id")
        end

        # Build the route's :as following Rails' nested-resources convention
        # so polymorphic_path([@user, :posts]) finds the route. Parents
        # contribute their singularised stem (`:user_id` → "user"); extra
        # static segments that aren't a parent's collection name (e.g.
        # `admin` in `users/:user_id/admin`) prefix the result for
        # disambiguation.
        parent_collection_segments = segments.each_with_index
          .select { |seg, i| i > 0 && seg.start_with?(":") }
          .map { |_, i| segments[i - 1] }
        extra_static = segments.reject { |s| s.empty? || s.start_with?(":") || parent_collection_segments.include?(s) }
        parent_prefix = parent_params.map { |p| p.to_s.delete_suffix("_id") }.join("_")
        as_prefix = [extra_static.join("_").presence, parent_prefix.presence].compact.join("_")
        as_base = [as_prefix.presence, route_key].compact.join("_")
        as_singular = [as_prefix.presence, singular_key].compact.join("_")

        # Trim whatever Rails has already accumulated in @scope[:as] —
        # Rails' name_for_action will re-add it. e.g. inside our auto-nest
        # wrap @scope[:as] is "user", so we only need to pass `:posts` for
        # the index route, and Rails composes back to `:user_posts`.
        existing_as = @scope[:as].to_s
        trim = ->(name) {
          if existing_as.present? && name.start_with?("#{existing_as}_")
            name[(existing_as.length + 1)..]
          else
            name
          end
        }
        as_to_pass = trim.call(as_base)
        singular_as_to_pass = trim.call(as_singular)

        controller_override = controller
        # Resolution order:
        #   1. explicit `controller:` wins (legacy escape hatch).
        #   2. if a namespace is in play AND the host has defined
        #      <Namespace>::ResourcesController (e.g.
        #      `Layered::Assistant::ResourcesController` including
        #      `Layered::Resource::Controller`), route to that — this is
        #      what lets engines wire the controller into their own
        #      ApplicationController for auth/authorize before_actions.
        #   3. otherwise fall back to the default. Use a leading "/" when
        #      inside a module scope so Rails treats the path as absolute
        #      and doesn't prepend the engine's module to it.
        controller = if controller
                       controller.to_s
                     elsif namespace && "#{namespace}::ResourcesController".safe_constantize
                       # Leading slash makes this absolute so a surrounding
                       # `module:` scope doesn't prepend its own namespace
                       # in front. Rails 8.1 rejects leading slashes in the
                       # `controller:` validation, so only add it when
                       # we're actually inside a module scope.
                       @scope[:module] ? "/#{namespace.underscore}/resources" : "#{namespace.underscore}/resources"
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

        Layered::Resource::Routing.register(as_base, resource_class_name,
                                            actions: actions,
                                            routes: @set,
                                            parent_params: parent_params,
                                            parent_collection_keys: parent_collection_keys,
                                            resource_name: route_key,
                                            member_actions: custom_member.map { |a| a[:action] },
                                            collection_actions: custom_collection.map { |a| a[:action] })

        route_defaults = (options[:defaults] || {}).merge(
          _layered_resource_route_key: as_base
        )
        options = options.except(:defaults, :as)

        if actions.include?(:index)
          get route_key, to: "#{controller}#index",
                         as: as_to_pass.to_sym,
                         defaults: route_defaults, **options
        end

        if actions.include?(:new)
          get "#{route_key}/new", to: "#{controller}#new",
                                 as: :"new_#{singular_as_to_pass}",
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
                      as: :"#{route[:action]}_#{as_to_pass}",
                      defaults: route_defaults, **options)
        end

        if actions.include?(:edit)
          get "#{route_key}/:id/edit", to: "#{controller}#edit",
                                       as: :"edit_#{singular_as_to_pass}",
                                       defaults: route_defaults, **options
        end

        member_named = false
        if actions.include?(:show)
          get "#{route_key}/:id", to: "#{controller}#show",
                                  as: singular_as_to_pass.to_sym,
                                  defaults: route_defaults, **options
          member_named = true
        end

        if actions.include?(:update)
          update_opts = { to: "#{controller}#update", defaults: route_defaults, **options }
          update_opts[:as] = member_named ? nil : singular_as_to_pass.to_sym
          patch "#{route_key}/:id", **update_opts
          member_named = true
        end

        if actions.include?(:destroy)
          destroy_opts = { to: "#{controller}#destroy", defaults: route_defaults, **options }
          destroy_opts[:as] = member_named ? nil : singular_as_to_pass.to_sym
          delete "#{route_key}/:id", **destroy_opts
        end

        custom_member.each do |route|
          public_send(route[:verb], "#{route_key}/:id/#{route[:action]}",
                      to: "#{controller}##{route[:action]}",
                      as: :"#{route[:action]}_#{singular_as_to_pass}",
                      defaults: route_defaults, **options)
        end
      end
    end
  end
end
