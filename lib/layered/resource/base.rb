module Layered
  module Resource
    class Base
      class << self
        def model(klass = nil)
          if klass
            @model = klass
          elsif instance_variable_defined?(:@model)
            @model
          elsif superclass < Layered::Resource::Base
            superclass.model
          else
            @model = name.delete_suffix("Resource").constantize
          end
        end

        def columns(value = nil)
          if value
            @columns = value
          else
            inherited_attribute(:@columns) || [{ attribute: :id }]
          end
        end

        def search_fields(value = nil)
          if value
            @search_fields = value
          else
            inherited_attribute(:@search_fields) || []
          end
        end

        def default_sort(value = nil)
          if value.is_a?(Hash)
            @default_sort = value
          else
            inherited_attribute(:@default_sort) || { attribute: :id, direction: :desc }
          end
        end

        def per_page(value = nil)
          if value
            @per_page = value
          else
            inherited_attribute(:@per_page) || 15
          end
        end

        def fields(value = nil)
          if value
            @fields = value
          else
            inherited_attribute(:@fields) || []
          end
        end

        def resolved_fields
          fields.map do |field|
            if field.key?(:required)
              field
            else
              field.merge(required: attribute_required?(field[:attribute]))
            end
          end
        end

        # Builds the args for `params.permit(*permitted_params)`. Each field
        # is permitted as a scalar by default. A `permit:` entry on a field
        # opts that field into the hash form: `permit: []` allows array
        # values (e.g. `documents: []` for `has_many_attached`), and
        # `permit: [:street, :city]` allows a nested hash with those keys
        # (e.g. `address_attributes: [:street, :city]` for accepts_nested).
        def permitted_params
          fields.map do |f|
            if f.key?(:permit)
              { f[:attribute] => f[:permit] }
            else
              f[:attribute]
            end
          end
        end

        def requires_distinct?
          model.ransackable_associations(self).any?
        end

        def scope(controller)
          if pundit_enabled?
            controller.send(:policy_scope, model)
          else
            model.all
          end
        end

        def build_record(controller)
          scope(controller).build
        end

        # Declares an ownership relationship between the resource's model and
        # an object the controller can produce (typically the signed-in user
        # or the current tenant).
        #
        #   owned_by :user                 # via :current_user
        #   owned_by :account, via: :current_account
        #
        # Behavioural shorthand for two override patterns at once:
        #   - `scope`        scopes records to the owner.
        #   - `build_record` assigns the owner on new records.
        #
        # When the controller's `via` accessor returns nil, `scope` returns
        # `model.none` so unauthenticated requests don't accidentally see the
        # full table. `use_pundit` takes over `scope` for the read filter
        # (Policy::Scope#resolve wins) but `owned_by` still drives owner
        # assignment on create.
        def owned_by(association, via: :current_user)
          @owned_by = { association: association, via: via }

          define_singleton_method(:scope) do |controller|
            if pundit_enabled?
              controller.send(:policy_scope, model)
            else
              owner = controller.public_send(via)
              owner.nil? ? model.none : model.where(association => owner)
            end
          end

          define_singleton_method(:build_record) do |controller|
            owner = controller.public_send(via)
            base = pundit_enabled? ? model : scope(controller)
            base.new(association => owner)
          end
        end

        # Opts the resource into Pundit. When enabled:
        #   - `scope(controller)` is `Pundit.policy_scope(current_user, model)`.
        #   - The controller calls `authorize(@record)` after loading a member
        #     record (show/edit/update/destroy) — Pundit raises on denial.
        #   - The `@resource_can_*` route-exposure flags are ANDed with the
        #     class-level policy (e.g. `policy(model).new?`) so action buttons
        #     hide automatically for users who can't perform the action.
        #
        # Per-record visibility (e.g. "this user can edit *this* record") is
        # available in views via the `resource_can?(:update, record)` helper,
        # which composes the route-exposure flag with the per-record policy.
        def use_pundit
          @use_pundit = true
        end

        def pundit_enabled?
          inherited_attribute(:@use_pundit) == true
        end

        def after_save_path(controller, _record)
          controller.layered_collection_path
        end

        def field_type_for(attribute)
          col = model.columns_hash[attribute.to_s]
          return :string unless col

          case col.type
          when :text then :text
          when :integer, :float, :decimal then :number
          when :boolean then :checkbox
          when :date then :date
          when :datetime then :datetime
          else :string
          end
        end

        def configure_ransack
          m = model
          return if m.instance_variable_get(:@_layered_resource_ransack_configured)

          # Capture the model's existing ransack methods (whether user-defined
          # or the framework default) before redefining them, and delegate
          # back for any caller that isn't this resource asking about its own
          # model. This preserves any allowlist the host app has set up, and
          # leaves cross-model association walks (e.g. Post.ransack walking to
          # User) to whatever the associated model has configured directly.
          original_attributes = m.method(:ransackable_attributes)
          original_associations = m.method(:ransackable_associations)
          host_associations_defined = m.singleton_methods(false).include?(:ransackable_associations)

          m.define_singleton_method(:ransackable_attributes) do |auth_object = nil|
            if auth_object.is_a?(Class) && auth_object < Layered::Resource::Base && auth_object.model == self
              db_columns = column_names
              attrs = auth_object.columns.map { |c| c[:attribute].to_s }.select { |a| db_columns.include?(a) }
              sort_attr = auth_object.default_sort[:attribute].to_s
              attrs |= [sort_attr] if db_columns.include?(sort_attr)
              attrs | auth_object.search_fields.map(&:to_s)
            else
              original_attributes.call(auth_object)
            end
          end

          # Cross-model ransack walks (e.g. sorting a Post index by
          # `user_name`) require both Post AND User to have ransackable
          # allowlists configured — and we can't allowlist on User without
          # silently patching a model the consumer didn't reference. Keep
          # the surface narrow: virtual columns are not ransackable by
          # default, so requests like `q[s]=user_name asc` are silently
          # ignored rather than 500ing. Hosts that genuinely want cross-
          # model sort/filter define `ransackable_associations` on the
          # parent model themselves (and allowlist attributes on the child)
          # — we defer to that explicit definition when present.
          m.define_singleton_method(:ransackable_associations) do |auth_object = nil|
            if auth_object.is_a?(Class) && auth_object < Layered::Resource::Base && auth_object.model == self
              host_associations_defined ? original_associations.call(auth_object) : []
            else
              original_associations.call(auth_object)
            end
          end

          m.instance_variable_set(:@_layered_resource_ransack_configured, true)
        end

        private

        # Walks the resource class ancestry to find the first ancestor that
        # has the given ivar set. Class-level ivars are not inherited in Ruby,
        # so we explicitly walk to give subclasses access to a parent's
        # declared columns/fields/etc. without redeclaring them.
        def inherited_attribute(ivar)
          klass = self
          while klass && klass <= Layered::Resource::Base
            return klass.instance_variable_get(ivar) if klass.instance_variable_defined?(ivar)

            klass = klass.superclass
          end
          nil
        end

        # An attribute is treated as required when it has a presence validator
        # that runs unconditionally on every save. Conditional (:if/:unless),
        # context-scoped (:on), and "skip when blank/nil" validators don't
        # qualify because they may not fire for the form being rendered.
        def attribute_required?(attribute)
          model.validators_on(attribute).any? { |v|
            v.is_a?(ActiveRecord::Validations::PresenceValidator) &&
              v.options.slice(:if, :unless, :on, :allow_nil, :allow_blank).empty?
          }
        end
      end
    end
  end
end
