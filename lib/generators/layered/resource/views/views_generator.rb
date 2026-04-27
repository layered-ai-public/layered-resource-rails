require "rails/generators/named_base"

module Layered
  module Resource
    module Generators
      # Copies the gem's view templates into the host app so they can be
      # edited freely. The controller's view-resolution escape hatch picks
      # them up automatically - no further wiring needed.
      #
      #   rails g layered:resource:views articles
      #
      # Generates app/views/layered/articles/{index,show,new,edit}.html.erb.
      class ViewsGenerator < ::Rails::Generators::NamedBase
        source_root Layered::Resource::Engine.root.join("app/views/layered/resource/resources")

        desc "Copy the gem's view templates into app/views/layered/<name>/ for full customisation."

        VIEWS = %w[index.html.erb show.html.erb new.html.erb edit.html.erb].freeze

        def copy_views
          VIEWS.each do |view|
            copy_file view, File.join("app/views/layered", resource_directory, view)
          end
        end

        def show_next_steps
          say ""
          say "Edit any of the templates in app/views/layered/#{resource_directory}/ - the gem will use them in place of its defaults."
          say ""
        end

        private

        # The controller's view-resolution escape hatch keys off the
        # plural name passed to `layered_resources`, ignoring any Rails
        # namespace. Mirror that here so generated files actually get
        # picked up.
        def resource_directory
          file_name.pluralize
        end

        def file_name
          @_file_name ||= super.singularize
        end
      end
    end
  end
end
