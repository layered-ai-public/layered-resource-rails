module Layered
  module Resource
    module Internal
      # Builds breadcrumb entries from parent route params.
      # Depends on @_route_entry being set by the controller's
      # load_layered_resource before_action.
      module Breadcrumbs
        extend ActiveSupport::Concern

        private

        # e.g. a route scoped under users/:user_id will produce
        # breadcrumbs like "Users" (linked) and "Alice" by looking up
        # the parent model and its layered index route.
        def layered_breadcrumbs
          @_layered_breadcrumbs ||= begin
            parent_param_keys = @_route_entry[:parent_params]
            parent_collection_keys = @_route_entry[:parent_collection_keys] || {}

            parent_param_keys.flat_map do |key|
              match = key.to_s.match(/\A(.+)_id\z/)
              next [] unless match

              model_name = match[1]
              model_class = model_name.classify.safe_constantize
              next [] unless model_class

              crumbs = []

              # Link to the parent's layered index if a route exists
              collection_key = parent_collection_keys[key]
              if collection_key
                collection_entry = Layered::Resource::Routing.lookup(collection_key)
                if collection_entry
                  rs = collection_entry[:routes] || Rails.application.routes
                  helper = :"#{collection_key}_path"
                  if rs.url_helpers.method_defined?(helper)
                    path = rs.url_helpers.send(helper, default_url_options)
                    crumbs << { label: model_class.model_name.human.pluralize, path: path }
                  end
                end
              end

              # Add the specific record breadcrumb
              record = model_class.find_by(id: params[key])
              if record
                label = record.try(:name) || record.try(:title) || "#{model_class.model_name.human} ##{record.id}"
                crumbs << { label: label, path: nil }
              end

              crumbs
            end
          end
        end
      end
    end
  end
end
