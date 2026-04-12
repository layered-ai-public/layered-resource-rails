module Layered
  module ManagedResource
    module Resource
      extend ActiveSupport::Concern

      included do
        raise "Layered::ManagedResource::Resource requires the ransack gem. Add `gem \"ransack\"` to your Gemfile." unless defined?(Ransack)
        raise "Layered::ManagedResource::Resource requires the pagy gem. Add `gem \"pagy\"` to your Gemfile." unless defined?(Pagy)
      end

      class_methods do
        def l_managed_resource_columns
          [{ attribute: :id }]
        end

        def l_managed_resource_search_fields
          []
        end

        def l_managed_resource_default_sort
          { attribute: :id, direction: :desc }
        end

        def l_managed_resource_per_page
          20
        end

        def l_managed_resource_distinct?
          ransackable_associations.any?
        end

        # --- CRUD support ---

        def l_managed_resource_fields
          []
        end

        def l_managed_resource_permitted_params
          l_managed_resource_fields.map { |f| f[:attribute] }
        end

        def l_managed_resource_build_record(controller)
          l_managed_resource_scope(controller).build
        end

        def l_managed_resource_scope(_controller)
          all
        end

        def l_managed_resource_after_save_path(controller, _record)
          url = controller.l_managed_resource_collection_url
          return url if url

          raise ActionController::RoutingError,
                "No :index route for #{model_name.human.pluralize}. " \
                "Add :index to only: or override l_managed_resource_after_save_path."
        end

        def l_managed_resource_field_type_for(attribute)
          col = columns_hash[attribute.to_s]
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

        # --- Ransack ---

        def ransackable_attributes(_auth_object = nil)
          attrs = l_managed_resource_columns.map { |c| c[:attribute].to_s }
          attrs |= l_managed_resource_search_fields.map(&:to_s)
          attrs
        end

        def ransackable_associations(_auth_object = nil)
          []
        end
      end
    end
  end
end
