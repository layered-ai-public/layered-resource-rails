module Layered
  module Resource
    # All the controller behaviour for a layered resource. Concern so that
    # host engines can declare their own `ResourcesController` inheriting
    # from their own ApplicationController and still pick up the full DSL:
    #
    #   class Layered::Assistant::ResourcesController < Layered::Assistant::ApplicationController
    #     include Layered::Resource::Controller
    #   end
    #
    # The default `Layered::Resource::ResourcesController < ::ApplicationController`
    # exists for non-engine host apps that just want everything wired up.
    module Controller
      extend ActiveSupport::Concern

      included do
        include Internal::Routing
        include Internal::Breadcrumbs
        include Internal::Columns

        helper Rails.application.routes.url_helpers
        helper Layered::Ui::TableHelper
        helper Layered::Ui::FormHelper
        helper Layered::Ui::RansackHelper
        helper Layered::Ui::PagyHelper
        helper Layered::Ui::BreadcrumbsHelper
        helper Layered::Resource::FiltersHelper

        before_action :load_layered_resource
        before_action :load_layered_member_record
        before_action :require_layered_fields, only: %i[new create edit update]
        before_action :set_layered_page_title

        helper_method :layered_routes
        helper_method :layered_collection_path
        helper_method :layered_member_path
        helper_method :layered_breadcrumbs
        helper_method :resource_can?
        helper_method :layered_record_label
      end

      def index
        apply_layered_filter_defaults
        @q = @resource.scope(self).ransack(params[:q], auth_object: @resource)
        if @q.sorts.empty?
          ds = @resource.default_sort
          @q.sorts = "#{ds[:attribute]} #{ds[:direction]}"
        end
        scope = @q.result(distinct: @resource.requires_distinct?)

        # Pagy rebuilds page links from the full request query; `fo` (the
        # one-shot open-this-tag's-popover param from the add-filter link)
        # must not ride along or paginating would reopen the popover.
        @pagy, @records = pagy(scope, limit: @resource.per_page,
                                      querify: ->(query) { query.delete("fo") })
        decorate_columns
      end

      def show
        @record = @resource.scope(self).find(params[:id])
        authorize_layered_record(@record)
        @page_title = layered_record_label(@record)
      end

      def new
        @record = @resource.build_record(self)
        authorize_layered_record(@record)
        @form_url = layered_collection_path
      end

      def create
        @record = @resource.build_record(self)
        authorize_layered_record(@record)
        @record.assign_attributes(layered_resource_params)

        if @record.save
          redirect_to @resource.after_save_path(self, @record),
                      notice: t("layered.resource.flash.created", model: @resource.model.model_name.human)
        else
          @form_url = layered_collection_path
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @record = @resource.scope(self).find(params[:id])
        authorize_layered_record(@record)
        @form_url = layered_member_path(@record)
        @page_title = "Edit #{layered_record_label(@record)}"
      end

      def update
        @record = @resource.scope(self).find(params[:id])
        authorize_layered_record(@record)
        if @record.update(layered_resource_params)
          redirect_to @resource.after_save_path(self, @record),
                      notice: t("layered.resource.flash.updated", model: @resource.model.model_name.human)
        else
          @form_url = layered_member_path(@record)
          @page_title = "Edit #{layered_record_label(@record)}"
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @record = @resource.scope(self).find(params[:id])
        authorize_layered_record(@record)
        redirect_path = @resource.after_save_path(self, @record)
        model_name = @resource.model.model_name.human
        begin
          if @record.destroy
            redirect_to redirect_path, notice: t("layered.resource.flash.deleted", model: model_name)
          else
            redirect_to redirect_path, alert: t("layered.resource.flash.not_deleted", model: model_name)
          end
        rescue ActiveRecord::InvalidForeignKey, ActiveRecord::DeleteRestrictionError
          redirect_to redirect_path,
                      alert: t("layered.resource.flash.dependent_records", model: model_name)
        end
      end

      # Composes the route-exposure flag for an action with the per-record
      # Pundit policy when `use_pundit` is enabled. `action` is one of
      # `:new`, `:create`, `:show`, `:edit`, `:update`, `:destroy`. Each key
      # gates the route of the same name and runs the matching Pundit query
      # (`new?`, `create?`, etc.). Pass a `record` to gate on an individual
      # record (e.g. inside the index row); omit it to fall back to the
      # class-level policy (`policy(@resource.model)`). Without `use_pundit`
      # this just returns the `@resource_can_*` flag.
      def resource_can?(action, record = nil)
        flag = case action
               when :new     then @resource_can_new
               when :create  then @resource_can_create
               when :show    then @resource_can_show
               when :edit    then @resource_can_edit
               when :update  then @resource_can_update
               when :destroy then @resource_can_destroy
               else raise ArgumentError, "unknown action #{action.inspect}"
               end
        return false unless flag
        return true unless @resource.pundit_enabled?

        policy(record || @resource.model).public_send(:"#{action}?")
      end

      # View lookup chain:
      #   1. layered/<resource_name>/                 — host-app per-resource override (e.g. `app/views/layered/posts/`)
      #   2. <controller's own inheritance prefixes>  — host's own layout chain
      #   3. layered/resource/resources/              — gem-shipped defaults (always last)
      #
      # The trailing default ensures custom subclasses (like
      # `CustomNamespace::ResourcesController` including `Layered::Resource::Controller`)
      # still find the gem's templates without re-declaring view paths.
      def _prefixes
        base = super
        prefixes = []
        prefixes << "layered/#{@layered_resource_name}" if @layered_resource_name
        prefixes.concat(base)
        prefixes << "layered/resource/resources" unless prefixes.include?("layered/resource/resources")
        prefixes
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
        @resource_can_new     = @crud_enabled && resource_actions.include?(:new)
        @resource_can_create  = @crud_enabled && resource_actions.include?(:create)
        @resource_can_edit    = @crud_enabled && resource_actions.include?(:edit)
        @resource_can_update  = @crud_enabled && resource_actions.include?(:update)
        @resource_can_destroy = resource_actions.include?(:destroy)
        @resource_can_show    = resource_actions.include?(:show)
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
        authorize_layered_record(@record)
      end

      # No-op unless the resource opts into Pundit. Defers to the host's
      # Pundit::Authorization mixin (typically included on ApplicationController).
      def authorize_layered_record(record)
        return unless @resource&.pundit_enabled?

        authorize(record, :"#{action_name}?")
      end

      # Merges each filter's `default:` into params[:q] when the request
      # carries none of that filter's keys, so both the Ransack query and the
      # filter-bar helpers see the same effective state (the tag shows the
      # default as active, and links/forms round-trip it explicitly). A key
      # that is present-but-blank means the user explicitly cleared a
      # defaulted filter — the remove/Clear links write blanks for exactly
      # this reason — so the default must NOT re-apply.
      def apply_layered_filter_defaults
        q = params[:q].respond_to?(:to_unsafe_h) ? params[:q].to_unsafe_h.stringify_keys : {}
        additions = {}

        @resource.resolved_filters.each do |filter|
          default = filter[:default]
          next if default.nil?
          next if filter[:param_keys].any? { |k| q.key?(k) }

          default = default.call if default.respond_to?(:call)
          if filter[:predicates]
            bounds = default.is_a?(Hash) ? default.symbolize_keys : { from: default }
            from_key, to_key = filter[:param_keys]
            additions[from_key] = bounds[:from] unless bounds[:from].nil?
            additions[to_key] = bounds[:to] unless bounds[:to].nil?
          else
            additions[filter[:param_keys].first] = filter[:multiple] ? Array(default) : default
          end
        end

        params[:q] = q.merge(additions) if additions.any?
      end

      def require_layered_fields
        return if @crud_enabled

        raise ActionController::RoutingError,
              "Define fields on #{@resource.name} to enable CRUD actions"
      end

      # Sets a default `@page_title` based on the action and resource model.
      # `show` and `edit` actions refine this with the loaded record's label.
      def set_layered_page_title
        human = @model.model_name.human
        @page_title = case action_name
                      when "new", "create" then "New #{human}"
                      when "edit", "update" then "Edit #{human}"
                      when "show" then human
                      else human.pluralize
                      end
      end

      # Renders a record as a human label, preferring the resource's primary
      # column (or the first column) and falling back to `to_s`.
      def layered_record_label(record)
        primary_column = @columns.find { |c| c[:primary] } || @columns.first
        value = primary_column && record.public_send(primary_column[:attribute])
        value.presence || record.to_s
      end

      def layered_resource_params
        params.require(@resource.model.model_name.param_key)
              .permit(*@resource.permitted_params)
      end
    end
  end
end
