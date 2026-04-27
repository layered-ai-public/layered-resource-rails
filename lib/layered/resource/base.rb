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

        def permitted_params
          fields.map { |f| f[:attribute] }
        end

        def requires_distinct?
          model.ransackable_associations(self).any?
        end

        def scope(_controller)
          model.all
        end

        def build_record(controller)
          scope(controller).build
        end

        def after_save_path(controller, _record)
          url = controller.layered_resource_collection_url
          return url if url

          raise ActionController::RoutingError,
                "No :index route for #{model.model_name.human.pluralize}. " \
                "Add :index to only: or override after_save_path."
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

          m.define_singleton_method(:ransackable_associations) do |auth_object = nil|
            if auth_object.is_a?(Class) && auth_object < Layered::Resource::Base && auth_object.model == self
              db_columns = column_names
              virtual_attrs = auth_object.columns.map { |c| c[:attribute].to_s }.reject { |a| db_columns.include?(a) }
              assoc_names = reflect_on_all_associations(:belongs_to).map { |a| a.name.to_s }
              virtual_attrs.filter_map { |attr|
                assoc_names.find { |assoc| attr.start_with?("#{assoc}_") }
              }.uniq
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
