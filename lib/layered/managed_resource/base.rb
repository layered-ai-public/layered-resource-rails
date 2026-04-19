module Layered
  module ManagedResource
    class Base
      class << self
        def model(klass = nil)
          if klass
            @model = klass
          else
            @model ||= name.delete_suffix("Resource").constantize
          end
        end

        def columns(value = nil)
          if value
            @columns = value
          else
            @columns || [{ attribute: :id }]
          end
        end

        def search_fields(value = nil)
          if value
            @search_fields = value
          else
            @search_fields || []
          end
        end

        def default_sort(value = nil)
          if value.is_a?(Hash)
            @default_sort = value
          else
            @default_sort || { attribute: :id, direction: :desc }
          end
        end

        def per_page(value = nil)
          if value
            @per_page = value
          else
            @per_page || 15
          end
        end

        def fields(value = nil)
          if value
            @fields = value
          else
            @fields || []
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

        def distinct?
          model.ransackable_associations.any?
        end

        def scope(_controller)
          model.all
        end

        def build_record(controller)
          scope(controller).build
        end

        def after_save_path(controller, _record)
          url = controller.managed_resource_collection_url
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

        def configure_ransack!
          return if @ransack_configured

          resource = self
          m = model

          m.define_singleton_method(:ransackable_attributes) do |_auth_object = nil|
            db_columns = column_names
            attrs = resource.columns.map { |c| c[:attribute].to_s }.select { |a| db_columns.include?(a) }
            attrs |= resource.search_fields.map(&:to_s)
            attrs
          end

          m.define_singleton_method(:ransackable_associations) do |_auth_object = nil|
            db_columns = column_names
            virtual_attrs = resource.columns.map { |c| c[:attribute].to_s }.reject { |a| db_columns.include?(a) }
            assoc_names = reflect_on_all_associations(:belongs_to).map { |a| a.name.to_s }
            virtual_attrs.filter_map { |attr|
              assoc_names.find { |assoc| attr.start_with?("#{assoc}_") }
            }.uniq
          end

          @ransack_configured = true
        end

        private

        def attribute_required?(attribute)
          model.validators_on(attribute).any? { |v|
            v.is_a?(ActiveRecord::Validations::PresenceValidator) && v.options.except(:message).empty?
          }
        end
      end
    end
  end
end
