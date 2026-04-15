module Layered
  module ManagedResource
    class ResourcesController < ::ApplicationController
      include Concerns::ManagedRouting
      include Concerns::ManagedBreadcrumbs
      include Concerns::ManagedColumns

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

      def require_managed_fields
        return if @crud_enabled

        raise ActionController::RoutingError,
              "Define fields on #{@resource.name} to enable CRUD actions"
      end

      def managed_resource_params
        params.require(@resource.model.model_name.param_key)
              .permit(*@resource.permitted_params)
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
