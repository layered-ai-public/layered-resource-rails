module Layered
  module Resource
    # View plumbing for the index filter bar. Filters are plain Ransack
    # predicates in the query string, so "applying" a filter is just a GET to
    # the collection path with the current `q` params plus/minus the filter's
    # own keys. Select-type controls apply instantly via links; range and
    # multi-select controls are small GET forms whose hidden fields round-trip
    # every *other* `q` param (search term, sort, other filters) so nothing is
    # lost across submits — no JavaScript involved.
    #
    # Picking a filter from the "Add filter" menu doesn't set a value — it
    # adds the filter as an *unset* chip whose popover holds the controls.
    # The top-level `f[]` param records which chips the user added and in
    # what order (new chips join the end of the row); it round-trips through
    # every link and form like the `q` params do and lives as long as the
    # chip does — setting a value keeps it, only the chip's ✕ removes it.
    module FiltersHelper
      BOOLEAN_FILTER_COLLECTION = [["Yes", "true"], ["No", "false"]].freeze

      def layered_filters
        @_layered_filters ||= @resource.resolved_filters
      end

      # The Ransack param scope this page's search object nests under
      # (virtually always "q").
      def layered_filter_scope
        ((@q && @q.context&.search_key) || :q).to_s
      end

      # The current same-scope Ransack params as a plain string-keyed hash —
      # the working state that apply/remove URLs and hidden fields are built
      # from. Values are the raw request strings/arrays.
      def layered_filter_query_params
        raw = params[layered_filter_scope]
        return {} unless raw.respond_to?(:to_unsafe_h)

        raw.to_unsafe_h.stringify_keys
      end

      # The `q` keys a filter owns, e.g. ["status_eq"], ["user_id_in"], or
      # ["created_at_gteq", "created_at_lteq"] for a range.
      def layered_filter_param_keys(filter)
        filter[:param_keys]
      end

      def layered_filter_active?(filter)
        layered_filter_param_keys(filter).any? { |k| layered_filter_query_params[k].present? }
      end

      # Declared filters added via the "Add filter" menu, in the order they
      # were added (`f[]` in the query string) — set or not, this is the
      # chip row's ordering. Unknown or stale entries are dropped.
      def layered_added_filter_attributes
        declared = layered_filters.map { |f| f[:attribute].to_s }
        Array(params[:f]).map(&:to_s).uniq & declared
      end

      def layered_filter_pending?(filter)
        !layered_filter_active?(filter) &&
          layered_added_filter_attributes.include?(filter[:attribute].to_s)
      end

      # URL the "Add filter" menu links to: current params plus this filter
      # as an unset chip at the end of the row.
      def layered_filter_add_path(filter)
        layered_filter_path_with(layered_filter_query_params,
                                 layered_added_filter_attributes | [filter[:attribute].to_s])
      end

      def layered_filter_label(filter)
        filter[:label] || @resource.model.human_attribute_name(filter[:attribute])
      end

      # Resolved [label, value] option pairs for select-type controls. Values
      # are strings so they compare directly against request params. Accepts
      # a collection as an array of values, [label, value] pairs, a callable,
      # or records (from a callable or a belongs_to's default klass.all).
      def layered_filter_collection(filter)
        return BOOLEAN_FILTER_COLLECTION if filter[:as] == :boolean

        raw = filter[:collection]
        raw = raw.call if raw.respond_to?(:call)
        raw ||= filter[:reflection]&.klass&.all
        Array(raw).map do |entry|
          if entry.is_a?(Array)
            [entry.first.to_s, entry.last.to_s]
          elsif entry.respond_to?(:to_key)
            [layered_filter_record_label(entry), entry.id.to_s]
          else
            [entry.to_s, entry.to_s]
          end
        end
      end

      def layered_filter_selected?(filter, value)
        current = layered_filter_query_params[layered_filter_param_keys(filter).first]
        Array(current).map(&:to_s).include?(value.to_s)
      end

      # URL applying `value` for a single-select/boolean filter, keeping every
      # other `q` param and dropping pagination. The filter's `f[]` entry is
      # kept — it holds the chip's position in the row.
      def layered_filter_apply_path(filter, value)
        q = layered_filter_query_params.except(*layered_filter_param_keys(filter))
        q[layered_filter_param_keys(filter).first] = value
        layered_filter_path_with(q)
      end

      # URL with the filter's own params (and pending `f[]` entry) stripped —
      # the chip's ✕ and the controls' Clear links. A filter with a `default:`
      # writes explicit blanks instead of dropping its keys: an absent key
      # would just re-apply the default on the next request.
      def layered_filter_remove_path(filter)
        q = layered_filter_query_params
        if filter[:default].nil?
          q = q.except(*layered_filter_param_keys(filter))
        else
          layered_filter_param_keys(filter).each { |k| q[k] = "" }
        end
        layered_filter_path_with(q, layered_added_filter_attributes - [filter[:attribute].to_s])
      end

      # Chip text, e.g. "Status: Published", "User: Alice, Bob",
      # "Created at: 2026-01-01 – 2026-06-30", "Comments count: ≥ 5".
      def layered_filter_chip_text(filter)
        "#{layered_filter_label(filter)}: #{layered_filter_chip_value(filter)}"
      end

      # Hidden inputs carrying every same-scope `q` param except the given
      # filter's own keys (and `except:` extras), plus all the `f[]` entries
      # (including the submitting filter's own — it keeps the chip's position),
      # so a form's GET submit preserves the search term, sort, the other
      # filters, and the chip row's order.
      def layered_filter_hidden_fields(filter = nil, except: [])
        skip = (filter ? layered_filter_param_keys(filter) : []) + Array(except).map(&:to_s)
        scope = layered_filter_scope

        fields = layered_filter_query_params.flat_map do |key, value|
          next [] if skip.include?(key) || value.is_a?(Hash)

          name = value.is_a?(Array) ? "#{scope}[#{key}][]" : "#{scope}[#{key}]"
          Array(value).map { |v| hidden_field_tag(name, v, id: nil) }
        end

        fields += layered_added_filter_attributes.map { |attr| hidden_field_tag("f[]", attr, id: nil) }

        safe_join(fields)
      end

      # The combined Ransack key the search box posts, mirroring
      # l_ui_search_form's simple mode (`:cont` predicate, `:or` combinator).
      def layered_search_field_key
        @resource.search_fields.map(&:to_s).join("_or_") + "_cont"
      end

      # Clear link for the search box that drops only the search term,
      # keeping active filters and sort.
      def layered_search_clear_path
        layered_filter_path_with(layered_filter_query_params.except(layered_search_field_key))
      end

      private

      def layered_filter_path_with(q, added = layered_added_filter_attributes)
        query = {}
        query[layered_filter_scope] = q if q.present?
        query[:f] = added if added.present?
        path = layered_collection_path
        query.present? ? "#{path}?#{query.to_query}" : path
      end

      def layered_filter_chip_value(filter)
        case filter[:as]
        when :select, :boolean
          labels = layered_filter_collection(filter).to_h { |label, value| [value, label] }
          current = Array(layered_filter_query_params[layered_filter_param_keys(filter).first])
          current.map { |v| labels.fetch(v.to_s, v.to_s) }.join(", ")
        when :date_range, :range
          from_key, to_key = layered_filter_param_keys(filter)
          from = layered_filter_query_params[from_key]
          to = layered_filter_query_params[to_key]
          if from.present? && to.present?
            "#{from} – #{to}"
          elsif from.present?
            "≥ #{from}"
          else
            "≤ #{to}"
          end
        else
          layered_filter_query_params[layered_filter_param_keys(filter).first]
        end
      end

      # Label for a record in a belongs_to select when no `collection:` is
      # given: the first present of name/title/label/email, else "Model #id".
      def layered_filter_record_label(record)
        %i[name title label email].each do |candidate|
          next unless record.respond_to?(candidate)

          value = record.public_send(candidate)
          return value.to_s if value.present?
        end
        "#{record.model_name.human} ##{record.id}"
      end
    end
  end
end
