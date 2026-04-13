module Layered
  module ManagedResource
    class ResourcesController < ::ApplicationController
      helper Rails.application.routes.url_helpers
      helper Layered::Ui::TableHelper
      helper Layered::Ui::FormHelper
      helper Layered::Ui::RansackHelper
      helper Layered::Ui::PaginationHelper
      helper Layered::Ui::BreadcrumbsHelper

      before_action :managed_resource_authenticate
      before_action :resolve_managed_resource
      before_action :require_managed_fields, only: %i[new create edit update]

      helper_method :managed_routes
      helper_method :managed_breadcrumbs

      def index
        @q = @resource.scope(self).ransack(params[:q])
        scope = @q.result(distinct: @resource.distinct?)
        if @q.sorts.empty?
          ds = @resource.default_sort
          scope = scope.order(ds[:attribute] => ds[:direction])
        end

        @pagy, @records = pagy(scope, limit: @resource.per_page)
        resolve_linked_columns
      end

      def new
        @record = @resource.build_record(self)
        @form_url = managed_collection_path
      end

      def create
        @record = @resource.build_record(self)
        @record.assign_attributes(managed_resource_params)

        if @record.save
          redirect_to @resource.after_save_path(self, @record),
                      notice: "#{@resource.model.model_name.human} created"
        else
          @form_url = managed_collection_path
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @record = @resource.scope(self).find(params[:id])
        @form_url = managed_member_path(@record)
      end

      def update
        @record = @resource.scope(self).find(params[:id])
        if @record.update(managed_resource_params)
          redirect_to @resource.after_save_path(self, @record),
                      notice: "#{@resource.model.model_name.human} updated"
        else
          @form_url = managed_member_path(@record)
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @record = @resource.scope(self).find(params[:id])
        redirect_path = @resource.after_save_path(self, @record)
        if @record.destroy
          redirect_to redirect_path,
                      notice: "#{@resource.model.model_name.human} deleted"
        else
          redirect_to redirect_path,
                      alert: "#{@resource.model.model_name.human} could not be deleted"
        end
      end

      def managed_resource_collection_url
        helper_name = :"managed_#{@managed_route_key}_path"
        managed_routes.send(helper_name) if managed_routes.respond_to?(helper_name)
      end

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

      # Builds breadcrumb entries from parent route params.
      # e.g. a route scoped under users/:user_id will produce a
      # breadcrumb like "User: Alice" by looking up the User record.
      def managed_breadcrumbs
        @_managed_breadcrumbs ||= begin
          parent_param_keys = @_route_entry[:parent_params]
          parent_param_keys.filter_map do |key|
            match = key.to_s.match(/\A(.+)_id\z/)
            next unless match

            model_name = match[1]
            model_class = model_name.classify.safe_constantize
            next unless model_class

            record = model_class.find_by(id: params[key])
            next unless record

            label = record.try(:name) || record.try(:title) || "#{model_class.model_name.human} ##{record.id}"
            { label: "#{model_class.model_name.human}: #{label}", path: nil }
          end
        end
      end

      # Looks up the resource class from the route registry and sets all
      # the instance variables the views need (@resource, @model, @columns,
      # @fields, and the @can_* permission flags).
      def resolve_managed_resource
        route_key = request.path_parameters.delete(:_managed_route_key)
        params.delete(:_managed_route_key)
        @_route_entry = Layered::ManagedResource::Routing.lookup(route_key)
        raise ActionController::RoutingError, "No managed resource registered for route" unless @_route_entry

        @resource = @_route_entry[:resource].safe_constantize
        unless @resource && @resource < Layered::ManagedResource::Base
          raise ActionController::RoutingError, "#{resource_name} is not a managed resource (must inherit from Layered::ManagedResource::Base)"
        end

        @resource.configure_ransack!

        @model = @resource.model
        @columns = @resource.columns
        @managed_route_key = route_key
        @fields = @resource.fields
        @crud_enabled = @fields.any?

        managed_actions = @_route_entry[:actions]
        @can_create = @crud_enabled && managed_actions.include?(:new)
        @can_update = @crud_enabled && managed_actions.include?(:edit)
        @can_destroy = managed_actions.include?(:destroy)
      end

      # Processes columns with a `link:` option, e.g.:
      #   { attribute: :posts_count, link: :users_posts }
      #
      # Looks up the named route in the registry and replaces the column
      # with a render proc that wraps the value in a link. Silently skips
      # columns whose route can't be resolved.
      def resolve_linked_columns
        view = view_context
        opts = default_url_options

        @columns = @columns.map do |col|
          next col if col[:render] || !col[:link]

          linked_key = col[:link].to_s
          linked_entry = Routing.lookup(linked_key)
          next col unless linked_entry

          rs = linked_entry[:routes] || Rails.application.routes
          parent_param = linked_entry[:parent_params].last
          path_helper = :"managed_#{linked_key}_path"
          next col unless parent_param && rs.url_helpers.method_defined?(path_helper)

          attr = col[:attribute]
          col.merge(
            render: ->(record) {
              path = rs.url_helpers.send(path_helper, opts.merge(parent_param => record.id))
              view.link_to record.public_send(attr).to_s, path, data: { turbo_frame: "_top" }
            }
          )
        end
      end

      def require_managed_fields
        return if @crud_enabled

        raise ActionController::RoutingError,
              "Define fields on #{@resource.name} to enable CRUD actions"
      end

      def managed_resource_params
        params.require(@resource.model.model_name.param_key)
              .permit(*@resource.permitted_params)
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

      def managed_resource_authenticate
        method = Layered::ManagedResource.managed_resource_before_action
        send(method) if method
      end

      def default_url_options
        main_app.default_url_options
      end
    end
  end
end
