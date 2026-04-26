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

        def apply_column_renderers
          @columns = @columns.map do |col|
            next col if col[:render]

            attr = col[:attribute]
            col.merge(
              render: ->(record) {
                raw = record.public_send(attr)
                raw.respond_to?(:strftime) ? raw.strftime("%-d %b %Y %H:%M") : raw
              }
            )
          end
        end

        # When :show is enabled, wraps the primary column's render proc to
        # link the cell to the show path. The "primary" column is the one
        # marked primary: true (or the first column if none is). Columns
        # that already declare a custom link: are left alone.
        def apply_primary_column_show_link
          return unless @can_show

          routes_proxy = layered_routes
          singular = @layered_route_key.singularize
          helper = :"layered_#{singular}_path"
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
                    "but that route has no parent params — link: only works for nested layered_resources"
            end

            path_helper = :"layered_#{linked_key}_path"
            unless rs.url_helpers.method_defined?(path_helper)
              raise ArgumentError,
                    "Column #{col[:attribute].inspect} on #{@resource.name} links to #{col[:link].inspect}, " \
                    "but #{path_helper} is not defined — does the route include :index?"
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
