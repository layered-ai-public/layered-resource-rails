module Layered
  module ManagedResource
    module Concerns
      # Processes columns with a `link:` option for the index table.
      # Depends on @columns being set by the controller's
      # resolve_managed_resource before_action.
      module ManagedColumns
        extend ActiveSupport::Concern

        private

        # Processes columns with a `link:` option, e.g.:
        #   { attribute: :posts_count, link: :users_posts }
        #
        # Looks up the named route in the registry and replaces the column
        # with a render proc that wraps the value in a badge link. Silently
        # skips columns whose route can't be resolved.
        def resolve_linked_columns
          resolve_column_renders
          resolve_column_links
        end

        def resolve_column_renders
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

        def resolve_column_links
          view = view_context
          opts = default_url_options

          @columns = @columns.map do |col|
            next col unless col[:link]

            linked_key = col[:link].to_s
            linked_entry = Routing.lookup(linked_key)
            next col unless linked_entry

            rs = linked_entry[:routes] || Rails.application.routes
            parent_param = linked_entry[:parent_params].last
            path_helper = :"managed_#{linked_key}_path"
            next col unless parent_param && rs.url_helpers.method_defined?(path_helper)

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
