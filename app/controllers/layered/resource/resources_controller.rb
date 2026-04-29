module Layered
  module Resource
    class ResourcesController < ::ApplicationController
      include Internal::Routing
      include Internal::Breadcrumbs
      include Internal::Columns

      helper Rails.application.routes.url_helpers
      helper Layered::Ui::TableHelper
      helper Layered::Ui::FormHelper
      helper Layered::Ui::RansackHelper
      helper Layered::Ui::PagyHelper
      helper Layered::Ui::BreadcrumbsHelper

      before_action :load_layered_resource
      before_action :load_layered_member_record
      before_action :require_layered_fields, only: %i[new create edit update]

      helper_method :layered_routes
      helper_method :layered_breadcrumbs

      def index
        @q = @resource.scope(self).ransack(params[:q], auth_object: @resource)
        if @q.sorts.empty?
          ds = @resource.default_sort
          @q.sorts = "#{ds[:attribute]} #{ds[:direction]}"
        end
        scope = @q.result(distinct: @resource.requires_distinct?)

        @pagy, @records = pagy(scope, limit: @resource.per_page)
        decorate_columns
      end

      def show
        @record = @resource.scope(self).find(params[:id])
        decorate_columns
      end

      def new
        @record = @resource.build_record(self)
        @form_url = layered_collection_path
      end

      def create
        @record = @resource.build_record(self)
        @record.assign_attributes(layered_resource_params)

        if @record.save
          redirect_to @resource.after_save_path(self, @record),
                      notice: "#{@resource.model.model_name.human} created"
        else
          @form_url = layered_collection_path
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @record = @resource.scope(self).find(params[:id])
        @form_url = layered_member_path(@record)
      end

      def update
        @record = @resource.scope(self).find(params[:id])
        if @record.update(layered_resource_params)
          redirect_to @resource.after_save_path(self, @record),
                      notice: "#{@resource.model.model_name.human} updated"
        else
          @form_url = layered_member_path(@record)
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

      def _prefixes
        return super unless @layered_resource_name

        ["layered/#{@layered_resource_name}", *super]
      end

      private

      # Looks up the resource class from the route registry and sets all
      # the instance variables the views need (@resource, @model, @columns,
      # @fields, and the @resource_can_* route-exposure flags).
      def load_layered_resource
        route_key = request.path_parameters.delete(:_layered_resource_route_key)
        params.delete(:_layered_resource_route_key)
        @_route_entry = Layered::Resource::Routing.lookup(route_key)
        raise ActionController::RoutingError, "No layered resource registered for route" unless @_route_entry

        @resource = @_route_entry[:resource].safe_constantize
        unless @resource && @resource < Layered::Resource::Base
          raise ActionController::RoutingError,
                "#{@_route_entry[:resource]} is not a layered resource (must inherit from Layered::Resource::Base)"
        end

        @resource.configure_ransack if Layered::Resource.auto_configure_ransack

        @model = @resource.model
        @columns = @resource.columns
        @layered_route_key = route_key
        @layered_resource_name = @_route_entry[:resource_name].presence || route_key
        @fields = @resource.resolved_fields
        @crud_enabled = @fields.any?

        resource_actions = @_route_entry[:actions]
        @resource_can_create = @crud_enabled && resource_actions.include?(:new)
        @resource_can_update = @crud_enabled && resource_actions.include?(:edit)
        @resource_can_destroy = resource_actions.include?(:destroy)
        @resource_can_show = resource_actions.include?(:show)
      end

      # For custom member actions declared in a `layered_resources` block,
      # populate @record from params[:id] so action bodies don't have to
      # repeat `@resource.scope(self).find(params[:id])`. Skip this with
      # `skip_before_action :load_layered_member_record, only: [:foo]` if
      # the action doesn't need the record (or shouldn't 404 on a missing
      # one).
      def load_layered_member_record
        return unless @_route_entry
        return unless params[:id]

        member_actions = @_route_entry[:member_actions] || []
        return unless member_actions.include?(action_name.to_sym)

        @record = @resource.scope(self).find(params[:id])
      end

      def require_layered_fields
        return if @crud_enabled

        raise ActionController::RoutingError,
              "Define fields on #{@resource.name} to enable CRUD actions"
      end

      def layered_resource_params
        params.require(@resource.model.model_name.param_key)
              .permit(*@resource.permitted_params)
      end

      def default_url_options
        main_app.default_url_options
      end
    end
  end
end
