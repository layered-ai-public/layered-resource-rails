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

            current_namespace = @_route_entry[:resource].to_s.deconstantize.presence

            parent_param_keys.flat_map do |key|
              match = key.to_s.match(/\A(.+)_id\z/)
              next [] unless match

              model_name = match[1]

              # Resolve the parent model class. Prefer the registered layered
              # resource entry (authoritative) when the parent is itself a
              # layered_resources. Otherwise try the current resource's
              # namespace before falling back to a top-level constant — this
              # lets a namespaced child have a plain `resources :provider`
              # parent that lives in the same namespace.
              collection_key = parent_collection_keys[key]
              collection_entry = collection_key && Layered::Resource::Routing.lookup(collection_key)
              model_class =
                if collection_entry
                  collection_entry[:resource].constantize.model
                elsif current_namespace
                  "#{current_namespace}::#{model_name.classify}".safe_constantize ||
                    model_name.classify.safe_constantize
                else
                  model_name.classify.safe_constantize
                end
              next [] unless model_class

              crumbs = []

              # Link to the parent's layered index if a route exists
              if collection_entry
                rs = collection_entry[:routes] || Rails.application.routes
                helper = :"#{collection_key}_path"
                if rs.url_helpers.method_defined?(helper)
                  ancestor_args = collection_entry[:parent_params].each_with_object({}) do |p, h|
                    h[p] = params[p]
                  end
                  if ancestor_args.values.all?(&:present?)
                    path = rs.url_helpers.send(helper, default_url_options.merge(ancestor_args))
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
