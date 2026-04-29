require "rails/generators/named_base"

module Layered
  module Resource
    module Generators
      # Creates a controller that inherits from
      # Layered::Resource::ResourcesController so the user can override
      # individual actions while keeping the rest of the gem's behaviour.
      #
      #   rails g layered:resource:controller articles
      #
      # Generates app/controllers/articles_controller.rb and prints the
      # routes change needed to wire it up.
      class ControllerGenerator < ::Rails::Generators::NamedBase
        source_root File.expand_path("templates", __dir__)

        desc "Generate a controller that inherits from Layered::Resource::ResourcesController."

        def create_controller_file
          path = File.join("app/controllers", class_path, "#{file_name}_controller.rb")
          full_path = File.join(destination_root, path)
          if File.exist?(full_path) && !options[:force]
            raise Thor::Error,
                  "#{path} already exists. The layered:resource:controller generator " \
                  "scaffolds a fresh subclass and would overwrite your existing file. " \
                  "Pass --force to overwrite, or delete/rename the existing file first."
          end
          template "controller.rb.tt", path
        end

        def show_routing_instructions
          say ""
          say "Point the route at the new controller:"
          say ""
          indent = "  "
          class_path.each_with_index do |segment, depth|
            say "#{indent * (depth + 1)}namespace :#{segment} do"
          end
          say "#{indent * (class_path.length + 1)}layered_resources :#{file_name}, controller: \"#{file_name}\""
          class_path.length.downto(1) do |depth|
            say "#{indent * depth}end"
          end
          say ""
        end

        private

        def file_name
          @_file_name ||= super.sub(/_?controller$/i, "")
        end
      end
    end
  end
end
