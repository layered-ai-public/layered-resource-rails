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
        # the parent model and its layered index route. A `root_breadcrumb`
        # declared on the resource is prepended to the trail.
        def layered_breadcrumbs
          @_layered_breadcrumbs ||= begin
            root_crumbs = [@resource.root_breadcrumb].compact
            parent_param_keys = @_route_entry[:parent_params]
            parent_collection_keys = @_route_entry[:parent_collection_keys] || {}

            current_namespace = @_route_entry[:resource].to_s.deconstantize.presence

            root_crumbs + parent_param_keys.flat_map do |key|
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

              # The parent's own ancestors, filled in from the current
              # request - needed by both of the parent's path helpers.
              if collection_entry
                rs = collection_entry[:routes] || Rails.application.routes
                ancestor_args = collection_entry[:parent_params].index_with { |p| params[p] }
                ancestor_args = nil unless ancestor_args.values.all?(&:present?)
              end

              # Link to the parent's layered index if a route exists
              if collection_entry && ancestor_args
                helper = :"#{collection_key}_path"
                if rs.url_helpers.method_defined?(helper)
                  path = rs.url_helpers.send(helper, default_url_options.merge(ancestor_args))
                  crumbs << { label: model_class.model_name.human.pluralize, path: path }
                end
              end

              # Add the specific record breadcrumb, linked to its own show
              # page when the parent resource has one - a crumb that isn't
              # the current page shouldn't be a dead end.
              record = model_class.find_by(id: params[key])
              if record
                label = record.try(:name) || record.try(:title) || "#{model_class.model_name.human} ##{record.id}"
                crumbs << { label: label, path: layered_parent_record_path(collection_entry, collection_key, ancestor_args, record) }
              end

              crumbs
            end
          end
        end

        # The parent record's show path, or nil when the parent isn't a
        # layered resource, doesn't route :show, or can't be addressed
        # from here.
        def layered_parent_record_path(collection_entry, collection_key, ancestor_args, record)
          return nil unless collection_entry && ancestor_args
          return nil unless collection_entry[:actions].include?(:show)

          rs = collection_entry[:routes] || Rails.application.routes
          helper = :"#{collection_key.to_s.singularize}_path"
          return nil unless rs.url_helpers.method_defined?(helper)

          rs.url_helpers.send(helper, default_url_options.merge(ancestor_args).merge(id: record.to_param))
        end
      end
    end
  end
end
