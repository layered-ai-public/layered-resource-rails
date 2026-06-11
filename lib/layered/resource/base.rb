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

        def resolved_fields
          fields.map do |field|
            if field.key?(:required)
              field
            else
              field.merge(required: attribute_required?(field[:attribute]))
            end
          end
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

        # An attribute is treated as required when it has a presence validator
        # that runs unconditionally on every save. Conditional (:if/:unless),
        # context-scoped (:on), and "skip when blank/nil" validators don't
        # qualify because they may not fire for the form being rendered.
        def attribute_required?(attribute)
          model.validators_on(attribute).any? { |v|
            v.is_a?(ActiveRecord::Validations::PresenceValidator) &&
              v.options.slice(:if, :unless, :on, :allow_nil, :allow_blank).empty?
          }
        end
      end
    end
  end
end
