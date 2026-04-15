module Layered
  module ManagedResource
    module Concerns
      # Route helper proxy and path generation for managed resources.
      # Depends on @_route_entry and @managed_route_key being set by
      # the controller's resolve_managed_resource before_action.
      module ManagedRouting
        extend ActiveSupport::Concern

        private

        # Returns an object that responds to managed route helpers (e.g.
        # managed_users_posts_path) with parent params already filled in
        # from the current request. Used by views to generate links without
        # needing to know the scope or parent context.
        def managed_routes
          @_managed_routes ||= begin
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

        def managed_collection_path
          helper_name = :"managed_#{@managed_route_key}_path"
          unless managed_routes.respond_to?(helper_name)
            raise ActionController::RoutingError,
                  "No collection route registered for #{@managed_route_key}. " \
                  "Include :index in the only: list, or override after_save_path."
          end
          managed_routes.send(helper_name)
        end

        def managed_member_path(record)
          singular = @managed_route_key.singularize
          helper_name = :"managed_#{singular}_path"
          unless managed_routes.respond_to?(helper_name)
            raise ActionController::RoutingError,
                  "No member route registered for #{@managed_route_key}. " \
                  "Include :update or :destroy in the only: list."
          end
          managed_routes.send(helper_name, record)
        end
      end
    end
  end
end
