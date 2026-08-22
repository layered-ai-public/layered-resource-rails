module Layered
  module Resource
    class Base
      class << self
        def model(klass = nil)
          if klass
            @model = klass
          elsif instance_variable_defined?(:@model)
            @model
          elsif superclass < Layered::Resource::Base
            superclass.model
          else
            @model = name.delete_suffix("Resource").constantize
          end
        end

        def columns(value = nil)
          if value
            @columns = value
          else
            inherited_attribute(:@columns) || [{ attribute: :id }]
          end
        end

        def search_fields(value = nil)
          if value
            @search_fields = value
          else
            inherited_attribute(:@search_fields) || []
          end
        end

        def search_placeholder(value = nil)
          if value
            @search_placeholder = value
          else
            inherited_attribute(:@search_placeholder) || default_search_placeholder
          end
        end

        # Declares a static crumb rendered before any derived breadcrumbs —
        # typically a link back to the host app's dashboard:
        #
        #   root_breadcrumb "Home", "/"
        #
        # Top-level resources otherwise have no trail at all; nested routes
        # prepend this crumb to the derived parent trail.
        def root_breadcrumb(label = nil, path = nil)
          if label
            @root_breadcrumb = { label: label, path: path }
          else
            inherited_attribute(:@root_breadcrumb)
          end
        end

        def default_sort(value = nil)
          if value.is_a?(Hash)
            @default_sort = value
          else
            inherited_attribute(:@default_sort) || { attribute: :id, direction: :desc }
          end
        end

        def per_page(value = nil)
          if value
            @per_page = value
          else
            inherited_attribute(:@per_page) || 15
          end
        end

        def fields(value = nil)
          if value
            @fields = value
          else
            inherited_attribute(:@fields) || []
          end
        end

        # The fields as the form layer wants them: each one's `required:`
        # resolved from its validators unless declared, and `permit:` dropped.
        # `permit:` is strong-parameters configuration read by
        # `permitted_params`; the form helper passes any key it does not
        # recognise through to the field's input, where a stray `permit`
        # renders as an HTML attribute (on a `select` or text input) or raises
        # (on a `combobox`, whose helper takes named options only).
        def resolved_fields
          fields.map do |field|
            field = infer_association_field(field.except(:permit))
            next field if field.key?(:required)

            field.merge(required: attribute_required?(field[:attribute]))
          end
        end

        # The attribute one of this resource's records is labelled by - in a
        # page title, a row's actions menu, or as an option in another
        # resource's picker. Defaults to the primary column (the column marked
        # `primary: true`, else the first), which is the label the index
        # already leads each row with. Declare it when that column is not the
        # record's name - a `primary:` column rendered by a `render:` proc,
        # say, or one that is not the record's own attribute at all:
        #
        #   label_attribute :title
        def label_attribute(value = nil)
          if value
            @label_attribute = value
          else
            inherited_attribute(:@label_attribute) ||
              (columns.find { |c| c[:primary] } || columns.first)&.fetch(:attribute, nil)
          end
        end

        def record_label(record)
          Layered::Resource.record_label(record, attribute: label_attribute)
        end

        # Declares structured filter controls for the index table. Each entry
        # is either a bare attribute (control + Ransack predicate inferred from
        # the column type, enum, or association) or an attribute with an
        # options hash overriding the inference:
        #
        #   filters :status,                       # enum     -> multi-select of its values
        #           :featured,                     # boolean  -> Yes / No
        #           :created_at,                   # datetime -> from / to range
        #           :comments_count,               # integer  -> number range
        #           :user                          # belongs_to -> multi-select
        #
        # Select-type filters (enum, belongs_to, collection) default to
        # multi-select via the `in` predicate; pass `multiple: false` for a
        # single-choice `eq` select.
        #
        # Recognised override keys: `as:` (control type), `collection:` (select
        # options — an array, an array of [label, value] pairs, or a callable
        # resolved per request), `multiple:` (multi-select via the `in`
        # predicate), `label:`, `pinned:` (tag always shown, never in the
        # add-filter menu, no remove ✕), and `default:` (value applied when
        # the request carries none — a scalar, `{ from:, to: }` for ranges,
        # or a callable resolved per request).
        def filters(*entries)
          if entries.empty?
            inherited_attribute(:@filters) || []
          else
            @filters = entries
          end
        end

        # Normalises `filters` into an array of control descriptors the view
        # layer renders and `patch_ransack` allowlists. Each descriptor carries
        # the Ransack attribute it keys on (`ransack_attribute` — the foreign
        # key for association filters), the inferred control (`as`), and the
        # collection/predicate metadata the control needs.
        def resolved_filters
          normalize_filter_entries(filters).map { |attribute, opts| build_filter(attribute, opts) }
        end

        # The own-model column names a filter set needs allowlisted for Ransack
        # (e.g. `status`, `created_at`, `user_id`). Association filters resolve
        # to the foreign-key column, so no association walk/join is required.
        def filter_attributes
          resolved_filters.map { |f| f[:ransack_attribute].to_s }
        end

        # Builds the args for `params.permit(*permitted_params)`. Each field
        # is permitted as a scalar by default. A `permit:` entry on a field
        # opts that field into the hash form: `permit: []` allows array
        # values (e.g. `documents: []` for `has_many_attached`), and
        # `permit: [:street, :city]` allows a nested hash with those keys
        # (e.g. `address_attributes: [:street, :city]` for accepts_nested).
        def permitted_params
          fields.map do |f|
            if f.key?(:permit)
              { f[:attribute] => f[:permit] }
            else
              f[:attribute]
            end
          end
        end

        def requires_distinct?
          model.ransackable_associations(self).any? do |assoc|
            model.reflect_on_association(assoc)&.collection?
          end
        end

        # Resolves `search_fields` entries that aren't columns on the
        # resource's own model but match Ransack's association-walk form
        # `<association>_<attribute>` (e.g. `:user_name` searches
        # `users.name` from a `belongs_to :user`). Returns hashes of
        # { association:, attribute:, klass: }. Longer association names
        # win when prefixes overlap (e.g. `author_profile_` over
        # `author_`), mirroring Ransack's greedy resolution.
        def association_search_fields
          reflections = model.reflect_on_all_associations
                             .reject(&:polymorphic?)
                             .sort_by { |r| -r.name.length }

          search_fields.filter_map do |field|
            field = field.to_s
            next if model.column_names.include?(field)

            reflection = reflections.find do |r|
              field.start_with?("#{r.name}_") &&
                r.klass.column_names.include?(field.delete_prefix("#{r.name}_"))
            end
            next unless reflection

            {
              association: reflection.name.to_s,
              attribute: field.delete_prefix("#{reflection.name}_"),
              klass: reflection.klass
            }
          end
        end

        def scope(controller)
          if pundit_enabled?
            controller.send(:policy_scope, model)
          else
            model.all
          end
        end

        def build_record(controller)
          scope(controller).build
        end

        # Declares an ownership relationship between the resource's model and
        # an object the controller can produce (typically the signed-in user
        # or the current tenant).
        #
        #   owned_by :user                 # via :current_user
        #   owned_by :account, via: :current_account
        #
        # Behavioural shorthand for two override patterns at once:
        #   - `scope`        scopes records to the owner.
        #   - `build_record` assigns the owner on new records.
        #
        # By default a nil owner (e.g. `current_user` returns nil because
        # auth wasn't wired up) raises loudly so the misconfiguration surfaces
        # immediately. Pass `allow_nil: true` for genuinely public-with-scope
        # behaviour, in which case `scope` falls back to `model.none` and
        # `build_record` assigns nil. `use_pundit` takes over `scope` for the
        # read filter (Policy::Scope#resolve wins) but `owned_by` still drives
        # owner assignment on create.
        def owned_by(association, via: :current_user, allow_nil: false)
          @owned_by = { association: association, via: via, allow_nil: allow_nil }

          # Pundit guards auth at the policy layer (policy.create?, etc.),
          # so when use_pundit is enabled we let nil owners pass and let
          # Pundit raise NotAuthorizedError. Without Pundit, we raise
          # MissingOwnerError on nil unless allow_nil: true.
          resolve_owner = lambda do |controller|
            owner = controller.public_send(via)
            if owner.nil? && !allow_nil && !pundit_enabled?
              raise Layered::Resource::MissingOwnerError,
                    "#{name}#owned_by(:#{association}) expected #{via} to return an owner but got nil. " \
                    "Ensure authentication is configured (e.g. before_action :authenticate_user!), " \
                    "or pass `allow_nil: true` to opt into public-with-scope behaviour."
            end
            owner
          end

          define_singleton_method(:scope) do |controller|
            if pundit_enabled?
              controller.send(:policy_scope, model)
            else
              owner = resolve_owner.call(controller)
              owner.nil? ? model.none : model.where(association => owner)
            end
          end

          define_singleton_method(:build_record) do |controller|
            owner = resolve_owner.call(controller)
            base = pundit_enabled? ? model : scope(controller)
            base.new(association => owner)
          end
        end

        # Opts the resource into Pundit. When enabled:
        #   - `scope(controller)` is `Pundit.policy_scope(current_user, model)`.
        #   - The controller calls `authorize(@record)` after loading a member
        #     record (show/edit/update/destroy) — Pundit raises on denial.
        #   - The `@resource_can_*` route-exposure flags are ANDed with the
        #     class-level policy (e.g. `policy(model).new?`) so action buttons
        #     hide automatically for users who can't perform the action.
        #
        # Per-record visibility (e.g. "this user can edit *this* record") is
        # available in views via the `resource_can?(:update, record)` helper,
        # which composes the route-exposure flag with the per-record policy.
        def use_pundit
          @use_pundit = true
        end

        def pundit_enabled?
          inherited_attribute(:@use_pundit) == true
        end

        def after_save_path(controller, _record)
          controller.layered_collection_path
        end

        def field_type_for(attribute)
          col = model.columns_hash[attribute.to_s]
          return :string unless col

          case col.type
          when :text then :text
          when :integer, :float, :decimal then :number
          when :boolean then :checkbox
          when :date then :date
          when :datetime then :datetime
          else :string
          end
        end

        def configure_ransack
          patch_ransack(model)
          # An association-walking search field (e.g. `:user_name`) is the
          # consumer explicitly referencing the associated model, so it also
          # gets the scoped patch — Ransack asks the *associated* model for
          # its ransackable_attributes when resolving the walk.
          association_search_fields.map { |a| a[:klass] }.uniq.each { |k| patch_ransack(k) }
        end

        private

        # Labels each search field via human_attribute_name so host-app i18n
        # (activerecord.attributes.<model>.<attr>) flows through. Association
        # walks label as "<association> <attribute>", each half resolved
        # against its own model's human names.
        def default_search_placeholder
          walks = association_search_fields.index_by { |a| "#{a[:association]}_#{a[:attribute]}" }

          labels = search_fields.map do |field|
            if (walk = walks[field.to_s])
              "#{model.human_attribute_name(walk[:association]).downcase} " \
                "#{walk[:klass].human_attribute_name(walk[:attribute]).downcase}"
            else
              model.human_attribute_name(field).downcase
            end
          end

          "Search by #{labels.join(', ')}"
        end

        # Installs scoped ransackable_attributes/ransackable_associations on
        # `m`. The overrides only answer when the `auth_object` is a layered
        # resource that references `m` — either as its own model, or via an
        # association-walking search field. Every other caller falls through
        # to the methods captured below (whether host-defined or the framework
        # default), so any allowlist the host app has set up is preserved.
        def patch_ransack(m)
          return if m.instance_variable_get(:@_layered_resource_ransack_configured)

          original_attributes = m.method(:ransackable_attributes)
          original_associations = m.method(:ransackable_associations)
          # Detect a host-defined override anywhere in the model's singleton
          # ancestry (Post, ApplicationRecord, ActiveRecord::Base, etc.).
          # Ransack supplies the default via a regular Module mixin, so its
          # `owner` is a Module but not a Class; an explicit `def self.x` in
          # any host class produces a singleton-class owner, which is a Class.
          host_attributes_defined = original_attributes.owner.is_a?(Class)
          host_associations_defined = original_associations.owner.is_a?(Class)

          m.define_singleton_method(:ransackable_attributes) do |auth_object = nil|
            unless auth_object.is_a?(Class) && auth_object < Layered::Resource::Base
              next original_attributes.call(auth_object)
            end

            if auth_object.model == self
              db_columns = column_names
              attrs = auth_object.columns.map { |c| c[:attribute].to_s }.select { |a| db_columns.include?(a) }
              sort_attr = auth_object.default_sort[:attribute].to_s
              attrs |= [sort_attr] if db_columns.include?(sort_attr)
              walks = auth_object.association_search_fields.map { |a| "#{a[:association]}_#{a[:attribute]}" }
              # Association-walking entries must NOT be allowlisted as
              # attributes here: Ransack treats an allowlisted name as a
              # literal column and emits `<table>.user_name` instead of
              # joining into the association.
              attrs |= (auth_object.search_fields.map(&:to_s) - walks)
              # Filter controls key on own-model columns (enum/boolean/date/
              # number columns, or a belongs_to's foreign key), so they fold
              # straight into the attribute allowlist alongside search fields.
              attrs |= auth_object.filter_attributes.select { |a| db_columns.include?(a) }
              # Self-referential walks (e.g. `parent_title` on a Post
              # `belongs_to :parent, class_name: "Post"`) land in this branch
              # too — the associated klass IS the resource's model — so the
              # walked attribute must be allowlisted here, not in the
              # other-resource branch below.
              attrs | auth_object.association_search_fields
                                 .select { |a| a[:klass] == self }
                                 .map { |a| a[:attribute] }
            else
              # A different resource asking about this model: answer only for
              # the attributes its association-walking search fields target
              # here (e.g. PostResource searching `user_name` asks User for
              # `name`), folding in the host's own allowlist when one exists.
              declared = auth_object.association_search_fields
                                    .select { |a| a[:klass] == self }
                                    .map { |a| a[:attribute] }
              if declared.any?
                base = host_attributes_defined ? original_attributes.call(auth_object) : []
                base | declared
              else
                original_attributes.call(auth_object)
              end
            end
          end

          # Associations become ransackable only when the resource explicitly
          # references them via an association-walking search field, or when
          # the host has defined its own allowlist. Everything else stays
          # narrow: requests like `q[s]=user_name asc` are silently ignored
          # rather than 500ing.
          m.define_singleton_method(:ransackable_associations) do |auth_object = nil|
            if auth_object.is_a?(Class) && auth_object < Layered::Resource::Base && auth_object.model == self
              base = host_associations_defined ? original_associations.call(auth_object) : []
              base | auth_object.association_search_fields.map { |a| a[:association] }
            else
              original_associations.call(auth_object)
            end
          end

          m.instance_variable_set(:@_layered_resource_ransack_configured, true)
        end

        # Walks the resource class ancestry to find the first ancestor that
        # has the given ivar set. Class-level ivars are not inherited in Ruby,
        # so we explicitly walk to give subclasses access to a parent's
        # declared columns/fields/etc. without redeclaring them.
        def inherited_attribute(ivar)
          klass = self
          while klass && klass <= Layered::Resource::Base
            return klass.instance_variable_get(ivar) if klass.instance_variable_defined?(ivar)

            klass = klass.superclass
          end
          nil
        end

        # Flattens the mixed positional/keyword `filters` form into
        # [attribute, options] pairs: bare symbols become [attr, {}]; a
        # trailing hash maps each attribute to its options hash.
        def normalize_filter_entries(entries)
          entries.flat_map do |entry|
            if entry.is_a?(Hash)
              entry.map { |attribute, opts| [attribute.to_sym, (opts || {}).symbolize_keys] }
            else
              [[entry.to_sym, {}]]
            end
          end
        end

        # Resolves one filter entry into a control descriptor, inferring the
        # control type and Ransack predicate from a belongs_to association, an
        # ActiveRecord enum, or the column type — unless an explicit `as:`
        # override is supplied.
        def build_filter(attribute, opts)
          reflection = belongs_to_reflection(attribute)
          label = opts[:label]

          descriptor =
            if reflection
              select_filter(attribute, reflection.foreign_key.to_sym, opts.fetch(:multiple, true),
                            opts[:collection], label, reflection: reflection)
            elsif model.defined_enums.key?(attribute.to_s)
              # Values are the enum's DB representation, not its keys — Ransack
              # compares the raw column, so `status_in[]=1` matches while
              # `status_in[]=published` would depend on attribute-type casting.
              collection = opts[:collection] || model.defined_enums[attribute.to_s].map { |k, v| [k.humanize, v] }
              select_filter(attribute, attribute, opts.fetch(:multiple, true), collection, label)
            else
              as = opts[:as] || default_filter_as(field_type_for(attribute), opts)
              multiple = opts.fetch(:multiple, as == :select)
              typed_filter(attribute, as, multiple, opts[:collection], label)
            end

          predicates = descriptor[:predicates] ? descriptor[:predicates].values : [descriptor[:predicate]]
          descriptor.merge(
            param_keys: predicates.map { |p| "#{descriptor[:ransack_attribute]}_#{p}" },
            pinned: opts.fetch(:pinned, false),
            default: opts[:default]
          )
        end

        def belongs_to_reflection(attribute)
          reflection = model.reflect_on_association(attribute)
          reflection if reflection&.belongs_to? && !reflection.polymorphic?
        end

        # Default control for a column type when no `as:` override is given.
        # A string/text column only becomes a select when a `collection:` is
        # supplied, otherwise it falls back to a "contains" text filter.
        def default_filter_as(type, opts)
          case type
          when :checkbox then :boolean
          when :date, :datetime then :date_range
          when :number then :range
          else opts.key?(:collection) ? :select : :string
          end
        end

        def select_filter(attribute, ransack_attribute, multiple, collection, label, reflection: nil)
          {
            attribute: attribute,
            ransack_attribute: ransack_attribute,
            as: :select,
            predicate: multiple ? :in : :eq,
            multiple: multiple,
            collection: collection,
            reflection: reflection,
            label: label
          }
        end

        def typed_filter(attribute, as, multiple, collection, label)
          base = { attribute: attribute, ransack_attribute: attribute, as: as,
                   multiple: multiple, collection: collection, label: label }
          case as
          when :select  then base.merge(predicate: multiple ? :in : :eq)
          when :boolean then base.merge(predicate: :eq)
          when :string  then base.merge(predicate: :cont)
          when :date_range, :range then base.merge(predicates: { from: :gteq, to: :lteq })
          else base.merge(predicate: :eq)
          end
        end

        # An attribute is treated as required when it has a presence validator
        # that runs unconditionally on every save. Conditional (:if/:unless),
        # context-scoped (:on), and "skip when blank/nil" validators don't
        # qualify because they may not fire for the form being rendered.
        def attribute_required?(attribute)
          # A `belongs_to` validates the presence of the *association*, not of
          # the foreign key the form posts, so the picker for one would always
          # look optional. Its validator is no use here either: Rails attaches
          # an `if:` that fires only while the key is nil or changed - an
          # internal optimisation, not conditionality the app asked for - which
          # the unconditional-only rule below would reject. The association's
          # own `optional:` is the declaration to read, resolved the way
          # ActiveRecord resolves it.
          if (reflection = belongs_to_reflection_for_key(attribute))
            optional = reflection.options[:optional]
            return optional.nil? ? !!model.belongs_to_required_by_default : !optional
          end

          model.validators_on(attribute).any? { |v|
            v.is_a?(ActiveRecord::Validations::PresenceValidator) &&
              v.options.slice(:if, :unless, :on, :allow_nil, :allow_blank).empty?
          }
        end

        # A field naming a `belongs_to`'s foreign key is a record picker, so it
        # renders as a single-select combobox over the associated records rather
        # than as the number the column happens to hold. Declaring `as:` opts
        # out, and `collection:` replaces the options (to scope or order them,
        # or to label them differently) while keeping the control.
        #
        # The default collection is a callable, so the query runs per request
        # rather than once at boot, and each record is labelled by the shared
        # `Layered::Resource.record_label`. Note that this does *not* consult
        # the associated model's own resource for its `label_attribute`: a
        # model can have several resources (a plain one and an admin variant,
        # say), so there is no single resource to ask. Pass `collection:` to
        # label by one deliberately:
        #
        #   { attribute: :user_id,
        #     collection: -> { User.kept.map { |u| [UserResource.record_label(u), u.id] } } }
        def infer_association_field(field)
          return field if field[:as]

          reflection = belongs_to_reflection_for_key(field[:attribute])
          return field if reflection.nil?

          collection = field[:collection] || lambda do
            reflection.klass.all.map { |record| [Layered::Resource.record_label(record), record.id] }
          end

          { as: :combobox, multiple: false, collection: collection }.merge(field)
        end

        # The `belongs_to` a field/attribute name is the foreign key of, if any.
        # Polymorphic associations are skipped: there is no single class whose
        # records could fill a picker.
        def belongs_to_reflection_for_key(key)
          key = key.to_s
          return nil unless model.column_names.include?(key)

          model.reflect_on_all_associations(:belongs_to)
               .reject(&:polymorphic?)
               .find { |reflection| reflection.foreign_key.to_s == key }
        end
      end
    end
  end
end
