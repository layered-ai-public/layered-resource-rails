module Layered
  module Resource
    module Internal
      # Decorates the column hashes set up by load_layered_resource with the
      # render procs the index view needs. Depends on @columns being set by
      # the controller's load_layered_resource before_action.
      module Columns
        extend ActiveSupport::Concern

        private

        # Walks @columns and installs the default render proc for any column
        # that doesn't already have one, then rewrites columns with a `link:`
        # option to render a badge linked to the named route.
        def decorate_columns
          apply_column_sortability
          apply_column_renderers
          apply_column_links
          apply_primary_column_show_link if action_name == "index"
        end

        # Marks columns sortable: false unless they map to a real DB column.
        # Virtual / association-derived columns (e.g. :user_name on Post) can't
        # be sorted by Ransack without the associated model also having
        # ransackable_attributes configured for the underlying field, so
        # leaving them sortable produces sort links that 500 when clicked.
        # Resources can opt back in by setting sortable: true explicitly and
        # are then responsible for the associated model's allowlist.
        def apply_column_sortability
          db_columns = @resource.model.column_names

          @columns = @columns.map do |col|
            next col if col.key?(:sortable)

            col.merge(sortable: db_columns.include?(col[:attribute].to_s))
          end
        end

        # Column rendering precedence:
        #   1. render: proc — escape hatch. Procs with arity 1 receive only
        #      the record. Anything else (fixed arity >= 2, or variadic /
        #      optional-arg procs with negative arity such as
        #      `->(record, view = nil)`) also receives view_context as a
        #      second arg, letting escape-hatch procs emit HTML via link_to
        #      / tag.* without ActionController::Base.helpers gymnastics.
        #      Normalised to single-arity here so downstream helpers
        #      (l_ui_table) keep calling proc.call(record).
        #   2. as: <type> — dispatch to a partial. Lookup order:
        #        a. app/views/layered/<resource_name>/columns/_<type>.html.erb
        #        b. app/views/layered/resource/columns/_<type>.html.erb
        #           (host-app override > gem default, via Rails view paths).
        #      Partial locals: (record, value, options). options is the
        #      column hash itself - partials read keys like :variants,
        #      :true_label, :format.
        #   3. Default: raw attribute value with a strftime fallback so
        #      datetime columns render readably without ceremony.
        def apply_column_renderers
          view = view_context

          @columns = @columns.map do |col|
            if (user_render = col[:render])
              arity = user_render.arity
              if arity == 1
                col
              elsif arity >= 2 || arity < 0
                col.merge(render: ->(record) { user_render.call(record, view) })
              else
                raise ArgumentError,
                      "render: proc for column #{col[:attribute].inspect} must accept " \
                      "(record) or (record, view_context); got arity #{arity}."
              end
            elsif col[:as]
              attr = col[:attribute]
              partial = resolve_column_partial(col[:as])
              options = col
              col.merge(
                render: ->(record) {
                  view.render(partial: partial, locals: { record: record, value: record.public_send(attr), options: options })
                }
              )
            else
              attr = col[:attribute]
              col.merge(
                render: ->(record) {
                  raw = record.public_send(attr)
                  raw.respond_to?(:strftime) ? raw.strftime("%-d %b %Y %H:%M") : raw
                }
              )
            end
          end
        end

        # Per-resource override wins; otherwise fall back to the host-wide
        # path. The host-wide path resolves to the host app's override (if
        # any) before the gem's built-in via the standard view-path chain.
        # Raises if neither exists - typo'd `as:` types should fail loudly,
        # not render an empty cell.
        def resolve_column_partial(type)
          per_resource = "layered/#{@layered_resource_name}/columns/#{type}"
          shared = "layered/resource/columns/#{type}"

          if lookup_context.exists?(type, ["layered/#{@layered_resource_name}/columns"], true)
            per_resource
          elsif lookup_context.exists?(type, ["layered/resource/columns"], true)
            shared
          else
            raise ArgumentError,
                  "No column partial found for as: #{type.inspect}. " \
                  "Looked for #{per_resource} and #{shared}. " \
                  "Run `rails g layered:resource:column #{type}` to scaffold one."
          end
        end

        # When :show is enabled, wraps the primary column's render proc to
        # link the cell to the show path. The "primary" column is the one
        # marked primary: true (or the first column if none is). Columns
        # that already declare a custom link: are left alone.
        def apply_primary_column_show_link
          return unless @resource_can_show

          routes_proxy = layered_routes
          singular = @layered_route_key.singularize
          helper = :"#{singular}_path"
          return unless routes_proxy.respond_to?(helper)

          primary_index = @columns.index { |c| c[:primary] } || 0
          view = view_context

          @columns = @columns.each_with_index.map do |col, i|
            next col unless i == primary_index
            next col if col[:link]

            inner_render = col[:render]
            col.merge(
              render: ->(record) {
                value = inner_render.call(record)
                view.link_to value, routes_proxy.send(helper, record), data: { turbo_frame: "_top" }
              }
            )
          end
        end

        # Rewrites columns with a `link:` option, e.g.:
        #   { attribute: :posts_count, link: :users_posts }
        #
        # Raises if the named route hasn't been registered, has no parent
        # params (so there's no way to pass the record id), or has no
        # generated path helper. Silent failure here turns a typo into a
        # mysterious unlinked column; better to surface it.
        def apply_column_links
          view = view_context
          opts = default_url_options

          @columns = @columns.map do |col|
            next col unless col[:link]

            linked_key = col[:link].to_s
            linked_entry = Layered::Resource::Routing.lookup(linked_key) ||
                           raise(ArgumentError, "Column #{col[:attribute].inspect} on #{@resource.name} has link: #{col[:link].inspect} but no layered_resources route is registered under that key")

            rs = linked_entry[:routes] || Rails.application.routes
            parent_param = linked_entry[:parent_params].last
            unless parent_param
              raise ArgumentError,
                    "Column #{col[:attribute].inspect} on #{@resource.name} links to #{col[:link].inspect}, " \
                    "but that route has no parent params - link: only works for nested layered_resources"
            end

            path_helper = :"#{linked_key}_path"
            unless rs.url_helpers.method_defined?(path_helper)
              raise ArgumentError,
                    "Column #{col[:attribute].inspect} on #{@resource.name} links to #{col[:link].inspect}, " \
                    "but #{path_helper} is not defined - does the route include :index?"
            end

            attr = col[:attribute]
            col.merge(
              render: ->(record) {
                value = record.public_send(attr)
                badge = view.content_tag(:span, value.to_s, class: "l-ui-badge l-ui-badge--default l-ui-badge--rounded")
                path = rs.url_helpers.send(path_helper, opts.merge(parent_param => record.id))
                view.link_to badge, path, data: { turbo_frame: "_top" }
              }
            )
          end
        end
      end
    end
  end
end
