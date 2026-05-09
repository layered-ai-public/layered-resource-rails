module Layered
  module Resource
    module Internal
      # Path generation for the current layered resource. Routes are
      # registered with Rails-standard `:as` names (e.g. `user_posts_path`),
      # so the helpers here can be backed either by named route lookup or
      # `polymorphic_path` — they're equivalent. We use named lookup for
      # the current resource's own paths because we already have the route
      # entry in hand from `load_layered_resource`; views and breadcrumbs
      # use polymorphic helpers when reaching across resources.
      module Routing
        extend ActiveSupport::Concern

        # Returns an object that responds to the route helpers (e.g.
        # users_posts_path) with parent params already filled in from
        # the current request. Used by views/columns to generate links
        # without needing to know the parent params.
        def layered_routes
          @_layered_routes ||= begin
            rs = @_route_entry[:routes] || Rails.application.routes
            proxy = Object.new
            proxy.singleton_class.include(rs.url_helpers)
            ctrl = self
            parent_values = request.path_parameters.slice(*@_route_entry[:parent_params])
            proxy.singleton_class.remove_method(:default_url_options) if proxy.singleton_class.method_defined?(:default_url_options)
            proxy.define_singleton_method(:default_url_options) { ctrl.send(:default_url_options).merge(parent_values) }
            proxy
          end
        end

        # Path to the current resource's collection (or one of its
        # collection-scoped actions, e.g. `:new`).
        def layered_collection_path(action: nil)
          base = action ? :"#{action}_#{@layered_route_key.singularize}" : @layered_route_key.to_sym
          helper = :"#{base}_path"
          unless layered_routes.respond_to?(helper)
            raise ActionController::RoutingError,
                  "No #{action || 'collection'} route registered for #{@layered_route_key}. " \
                  "Include the matching action in only:."
          end
          layered_routes.send(helper)
        end

        # Path to a member of the current resource (or a member-scoped
        # action like `:edit`).
        def layered_member_path(record, action: nil)
          singular = @layered_route_key.singularize
          base = action ? :"#{action}_#{singular}" : singular.to_sym
          helper = :"#{base}_path"
          unless layered_routes.respond_to?(helper)
            raise ActionController::RoutingError,
                  "No #{action || 'member'} route registered for #{@layered_route_key}. " \
                  "Include the matching action in only:."
          end
          layered_routes.send(helper, record)
        end
      end
    end
  end
end
