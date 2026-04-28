require "rails/generators/named_base"

module Layered
  module Resource
    module Generators
      # Generates an `app/layered_resources/<name>_resource.rb` file and
      # appends a `layered_resources :name` route. Use
      # `rails g layered:resource:scaffold` for the full one-shot that also
      # creates the model and migration.
      #
      #   rails g layered:resource article title:string body:text
      class ResourceGenerator < ::Rails::Generators::NamedBase
        source_root File.expand_path("templates", __dir__)

        argument :attributes, type: :array, default: [], banner: "field[:type][:index] field[:type][:index]"

        class_option :skip_route, type: :boolean, default: false,
                                  desc: "Skip appending a layered_resources route"

        desc "Generate an app/layered_resources/<name>_resource.rb file and a route."

        def create_resource_file
          template "resource.rb.tt",
                   File.join("app/layered_resources", "#{singular_name}_resource.rb")
        end

        def add_route
          return if options[:skip_route]

          route "layered_resources :#{plural_name}"
        end

        private

        def singular_name
          file_name.singularize
        end

        def plural_name
          file_name.pluralize
        end

        def resource_class_name
          singular_name.camelize
        end

        def column_attributes
          attributes.reject { |a| a.reference? || a.password_digest? }
        end

        def field_attributes
          column_attributes
        end

        def field_as(attr)
          case attr.type
          when :text then ", as: :text"
          end
        end
      end
    end
  end
end
