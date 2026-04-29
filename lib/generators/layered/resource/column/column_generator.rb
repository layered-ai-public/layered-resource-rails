require "rails/generators/base"

module Layered
  module Resource
    module Generators
      # Ejects a built-in column partial into the host app, or scaffolds a
      # custom one. Lookup order at runtime is per-resource → host-wide →
      # gem default, so ejected partials override the gem's built-ins.
      #
      #   rails g layered:resource:column badge              # → app/views/layered/resource/columns/_badge.html.erb
      #   rails g layered:resource:column badge questions    # → app/views/layered/questions/columns/_badge.html.erb
      #   rails g layered:resource:column priority_badge     # → scaffold a new type (host-wide)
      class ColumnGenerator < ::Rails::Generators::Base
        BUILT_INS = %w[text datetime badge boolean].freeze

        argument :type, type: :string, banner: "type"
        argument :resource, type: :string, default: nil, optional: true,
                            banner: "[resource]"

        source_root Layered::Resource::Engine.root.join("app/views/layered/resource/columns")

        desc "Eject a built-in column partial, or scaffold a custom one."

        def create_partial
          if BUILT_INS.include?(type)
            copy_file "_#{type}.html.erb", target_path
          else
            create_file target_path, scaffold_template
          end
        end

        def show_next_steps
          say ""
          say "Edit #{target_path} to customise rendering."
          say ""
          say "Use it from a resource with:"
          say "  columns [{ attribute: :something, as: :#{type} }]"
          say ""
        end

        private

        def target_path
          dir = resource.present? ? "app/views/layered/#{resource}/columns" : "app/views/layered/resource/columns"
          File.join(dir, "_#{type}.html.erb")
        end

        # Starter content for a new (non-built-in) column type. Locals
        # contract matches the runtime: (record, value, options).
        def scaffold_template
          <<~ERB
            <%# Column partial for as: :#{type}.
                Locals:
                  record  - the model instance
                  value   - record.public_send(column_attribute)
                  options - the column hash (read keys like :variants, :format) %>
            <%= value %>
          ERB
        end
      end
    end
  end
end
