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
    # adds the filter as an *unset* tag whose popover holds the controls.
    # The top-level `f[]` param records which tags the user added and in
    # what order (new tags join the end of the row); it round-trips through
    # every link and form like the `q` params do and lives as long as the
    # tag does — setting a value keeps it, only the tag's ✕ removes it.
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

        raw.to_unsafe_h.stringify_keys.transform_values { |v| layered_filter_normalize_value(v) }
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
      # tag row's ordering. Unknown or stale entries are dropped.
      def layered_added_filter_attributes
        declared = layered_filters.map { |f| f[:attribute].to_s }
        Array(params[:f]).map(&:to_s).uniq & declared
      end

      def layered_filter_pending?(filter)
        !layered_filter_active?(filter) &&
          layered_added_filter_attributes.include?(filter[:attribute].to_s)
      end

      # URL the "Add filter" menu links to: current params plus this filter
      # as an unset tag at the end of the row. The `fo` param asks that
      # render to open the new tag's popover, so the controls are ready
      # without a second click.
      def layered_filter_add_path(filter)
        attribute = filter[:attribute].to_s
        layered_filter_path_with(layered_filter_query_params,
                                 layered_added_filter_attributes | [attribute],
                                 open: attribute)
      end

      # The filter whose tag popover should open on this render (via the
      # tag popover's `open:` option) — the one-shot `fo` param carried only
      # by the "Add filter" menu links. Unlike `q` and `f[]` it never
      # round-trips: forms and links rebuild their URLs without it and the
      # pagy call strips it from page links, so the popover opens once and
      # stays closed thereafter.
      def layered_auto_open_filter
        layered_filters.find { |f| f[:attribute].to_s == params[:fo] } if params[:fo].present?
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

        # Memoised per render: a callable collection (or a belongs_to's default
        # `klass.all`) is a query, and the control, the size check behind
        # `layered_filter_control`, and the tag text all ask for it.
        @_layered_filter_collections ||= {}
        @_layered_filter_collections[filter[:attribute]] ||= begin
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
      end

      # The control this filter actually renders — `filter[:as]` for everything
      # but a select, which resolves between the plain list and the combobox.
      # The choice is made here rather than in `resolved_filters` because it
      # depends on how many options the collection turns out to hold, and a
      # callable collection only resolves per request.
      #
      # A `url:` filter is always a combobox (its options are fetched as the
      # user types, so there is nothing to render up front and nothing to
      # count); a declared `as:` is honoured as declared; otherwise a list
      # longer than `Layered::Resource.filter_combobox_threshold` switches to
      # the combobox, since neither a checkbox list nor a menu of links scales.
      def layered_filter_control(filter)
        return filter[:as] unless Layered::Resource::Base::SELECT_FILTER_CONTROLS.include?(filter[:as])
        return :combobox if filter[:as] == :combobox || filter[:url].present?
        return :select if filter[:as_declared]

        layered_filter_collection(filter).size > Layered::Resource.filter_combobox_threshold ? :combobox : :select
      end

      # A filter's `url:`, resolved in the view so it can be given as a
      # callable wrapping a path helper (`-> { options_users_path }`) — the
      # form a resource class can write without route helpers at load time.
      def layered_filter_url(filter)
        url = filter[:url]
        url.respond_to?(:call) ? instance_exec(&url) : url
      end

      # The `l_ui_combobox` options for a filter rendered as a combobox:
      # remote (`url:`) or local (`collection:`), never both, plus whatever
      # combobox options the filter declared. Selections go over as
      # [label, value] pairs because a remote combobox has no collection in
      # the browser to look a label up in.
      def layered_filter_combobox_options(filter)
        options = {
          label: layered_filter_label(filter),
          multiple: !!filter[:multiple],
          selected: layered_filter_selected_options(filter)
        }
        if (url = layered_filter_url(filter)).present?
          options[:url] = url
        else
          options[:collection] = layered_filter_collection(filter)
        end
        options[:min_chars] = filter[:min_chars] if filter[:min_chars]
        options[:text] = filter[:text] if filter[:text]
        options
      end

      # The filter's current values as [label, value] pairs — the combobox's
      # selections and the tag's text come from the same place, so they always
      # agree. Labels come from the collection when there is one; a remote
      # filter has none, so an association's are read from the records
      # themselves and anything else shows the raw value.
      def layered_filter_selected_options(filter)
        values = Array(layered_filter_query_params[layered_filter_param_keys(filter).first])
                   .map(&:to_s).reject(&:blank?)
        return [] if values.empty?

        labels = layered_filter_option_labels(filter, values)
        values.map { |value| [labels.fetch(value, value), value] }
      end

      def layered_filter_selected?(filter, value)
        current = layered_filter_query_params[layered_filter_param_keys(filter).first]
        Array(current).map(&:to_s).include?(value.to_s)
      end

      # URL applying `value` for a single-select/boolean filter, keeping every
      # other `q` param and dropping pagination. The filter's `f[]` entry is
      # kept — it holds the tag's position in the row.
      def layered_filter_apply_path(filter, value)
        q = layered_filter_query_params.except(*layered_filter_param_keys(filter))
        q[layered_filter_param_keys(filter).first] = value
        layered_filter_path_with(q)
      end

      # URL with the filter's own params (and pending `f[]` entry) stripped —
      # the tag's ✕ and the controls' Clear links. A filter with a `default:`
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

      # Tag text, e.g. "Status: Published", "User: Alice, Bob",
      # "Created at: 2026-01-01 – 2026-06-30", "Comments count: ≥ 5".
      def layered_filter_tag_text(filter)
        "#{layered_filter_label(filter)}: #{layered_filter_tag_value(filter)}"
      end

      # Hidden inputs carrying every same-scope `q` param except the given
      # filter's own keys (and `except:` extras), plus all the `f[]` entries
      # (including the submitting filter's own — it keeps the tag's position),
      # so a form's GET submit preserves the search term, sort, the other
      # filters, and the tag row's order.
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

      # The collection path carrying the full current state (`q` and `f[]`),
      # minus pagination. Links that rebuild their query from a base URL —
      # the table's sort links replace only `q[s]` on it — must start from
      # this, not the bare collection path, or they drop search and filters.
      def layered_filtered_collection_path
        layered_filter_path_with(layered_filter_query_params)
      end

      private

      def layered_filter_path_with(q, added = layered_added_filter_attributes, open: nil)
        query = {}
        query[layered_filter_scope] = q if q.present?
        query[:f] = added if added.present?
        query[:fo] = open if open.present?
        path = layered_collection_path
        query.present? ? "#{path}?#{query.to_query}" : path
      end

      def layered_filter_tag_value(filter)
        case filter[:as]
        when :select, :combobox, :boolean
          layered_filter_selected_options(filter).map(&:first).join(", ")
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

      # Value => label for the filter's currently-set values. A remote filter
      # has no collection to read them from, so an association's are looked up
      # by id; anything else (a remote filter over a plain column) resolves to
      # nothing and the value stands in for its own label.
      def layered_filter_option_labels(filter, values)
        if filter[:url].present?
          reflection = filter[:reflection]
          return {} if reflection.nil?

          reflection.klass.where(id: values)
                    .to_h { |record| [record.id.to_s, layered_filter_record_label(record)] }
        else
          layered_filter_collection(filter).to_h { |label, value| [value, label] }
        end
      end

      # Drops the blank value a combobox posts ahead of its selections (there
      # so that clearing every token submits an empty collection rather than
      # omitting the parameter — Ransack prunes it from the query itself). An
      # array left with nothing becomes an explicit blank, the same shape the
      # Clear link writes, so a cleared filter reads as inactive and a
      # `default:` doesn't immediately re-apply.
      def layered_filter_normalize_value(value)
        return value unless value.is_a?(Array)

        pruned = value.reject(&:blank?)
        pruned.empty? ? "" : pruned
      end

      # Label for a record in a belongs_to select when no `collection:` is
      # given. The associated model is another resource's business, not this
      # one's, so there is no `label_attribute` to ask for: the shared
      # fallbacks (name/title/label/email, else "Model #id") do the labelling.
      def layered_filter_record_label(record)
        Layered::Resource.record_label(record)
      end
    end
  end
end
