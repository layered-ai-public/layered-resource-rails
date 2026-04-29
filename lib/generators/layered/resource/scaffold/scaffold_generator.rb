require "rails/generators/named_base"
require "generators/layered/resource/resource_generator"
require "generators/layered/resource/views/views_generator"

module Layered
  module Resource
    module Generators
      # One-shot scaffolder: generates the migration + model (via Rails'
      # built-in model generator), an `app/layered_resources/<name>_resource.rb`
      # (via `layered:resource`), and appends a `layered_resources :name` route.
      # Views are intentionally left to the gem's defaults - run
      # `rails g layered:resource:views <name>` to eject them.
      #
      #   rails g layered:resource:scaffold article title:string body:text
      class ScaffoldGenerator < ::Rails::Generators::NamedBase
        argument :attributes, type: :array, default: [], banner: "field[:type][:index] field[:type][:index]"

        class_option :skip_model, type: :boolean, default: false,
                                  desc: "Skip generating the migration and model (use when they already exist)"
        class_option :actions, type: :array, default: nil, banner: "index show new create edit update destroy",
                               desc: "Restrict the generated route to these actions (passed to layered_resources only:)"
        class_option :except, type: :array, default: nil, banner: "destroy",
                              desc: "Exclude these actions from the generated route (passed to layered_resources except:)"
        class_option :controller, type: :boolean, default: false,
                                  desc: "Also eject a controller (invokes layered:resource:controller) and wire it into the route"
        class_option :views, type: :boolean, default: false,
                             desc: "Also eject the view templates (invokes layered:resource:views)"

        desc "Generate a model, migration, resource class, and route in one shot."

        def create_model
          return if options[:skip_model]

          invoke "model", [singular_name, *attributes.map(&:to_s)]
        end

        def create_resource_file
          invoke ResourceGenerator, [singular_name, *attributes.map(&:to_s)], skip_route: true
        end

        def eject_controller
          invoke "layered:resource:controller", [plural_name] if options[:controller]
        end

        def eject_views
          invoke ViewsGenerator, [plural_name] if options[:views]
        end

        def add_route
          route "layered_resources :#{plural_name}#{route_controller_option}#{route_action_filter}"
        end

        def show_next_steps
          say ""
          say "Next steps for app/layered_resources/#{singular_name}_resource.rb:"
          say "  - Add `validates` calls to #{resource_class_name} for any required fields - the form marks fields required based on unconditional presence validators."
          say "  - Consider `default_sort attribute: :created_at, direction: :desc` (or another column) so the index has a stable order."
          say "  - Consider `search_fields [...]` listing the columns the index search box should match against."
          say ""
        end

        private

        def route_controller_option
          ", controller: \"#{plural_name}\"" if options[:controller]
        end

        def route_action_filter
          if options[:actions].present?
            ", only: #{action_list(options[:actions])}"
          elsif options[:except].present?
            ", except: #{action_list(options[:except])}"
          end
        end

        def action_list(actions)
          "[#{actions.map { |a| ":#{a}" }.join(', ')}]"
        end

        def singular_name
          file_name.singularize
        end

        def plural_name
          file_name.pluralize
        end

        def resource_class_name
          singular_name.camelize
        end
      end
    end
  end
end
