# Changelog

All notable changes to this project will be documented in this file. This project follows [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-08-30

Initial release.

### Resource DSL

- `Layered::Resource::Base` DSL: `model`, `columns`, `fields`, `search_fields`, `default_sort`, `per_page`.
- `label_attribute :title` — the attribute a record is labelled by wherever the gem names one (the `show`/`edit` page titles, a row's actions menu, and its options in another resource's picker). Defaults to the primary column. A record whose labelling attribute is blank falls back through `name`/`title`/`label`/`email`, then the model's own `to_s` when it defines one, then `"Post #12"`.
- Resource inheritance for namespaced variants (e.g. `Admin::PostResource`), with `inherited_attribute` walking the ancestor chain so subclasses pick up their parent's declarations.
- Escape hatches: `scope`, `build_record`, and `after_save_path`.

### Routing and controllers

- `layered_resources` route helper with full CRUD, plus `only:`/`except:` to restrict actions. Incoherent combinations (`:new` without `:create`) raise at route-definition time rather than 404ing later.
- `layered_resources :foo, namespace: "Foo::Bar"` derives the resource class as `Foo::Bar::FooResource` and routes to `Foo::Bar::ResourcesController` when one is defined — the supported path for mounting resources inside an engine.
- `Layered::Resource::Controller` concern. An engine can define its own `<Namespace>::ResourcesController` inheriting from its own `ApplicationController` and `include Layered::Resource::Controller`, keeping auth/authorize `before_action`s wired correctly.
- Auth inherited from the host app's `ApplicationController`, so its `before_action`s (Devise and friends) apply with no extra configuration.
- `owned_by` scopes a resource to its owner, and raises `Layered::Resource::MissingOwnerError` when `via` returns nil so auth misconfiguration surfaces loudly instead of silently 404ing every request. Pass `allow_nil: true` to opt into public-with-scope behaviour. (No-op under `use_pundit`, where Pundit handles the policy gate.)
- `destroy` rescues `ActiveRecord::InvalidForeignKey` and `ActiveRecord::DeleteRestrictionError`, redirecting to the index with a flash rather than raising a 500.

### Index: search, sort, filters, pagination

- Index search, sort, and pagination via Ransack and Pagy.
- `filters :status, :created_at, user: { multiple: true }` — structured index filters rendered as an "Add filter" popover plus removable chips. Picking a filter adds an unset chip to the end of the row; its popover holds the controls, its ✕ removes it. Control and Ransack predicate are inferred from the column type (enum/`belongs_to` → multi-select via `_in`, with `multiple: false` for single-choice `_eq`; boolean → Yes/No; date/datetime → date range; numeric → number range; string → contains), and are overridable per attribute with `as:`/`collection:`/`multiple:`/`label:`/`pinned:`/`default:`. Pinned filters render as always-shown chips (no ✕, never in the add menu — which disappears entirely once every filter is pinned); a default applies when the request carries no state for the filter, and clearing writes an explicit blank so it does not re-apply. Filters, search, and sort round-trip each other as hidden fields, so they compose in the URL with no JavaScript.
- A select-type filter with more than `Layered::Resource.filter_combobox_threshold` (10) options renders as a type-ahead combobox rather than a checkbox list (or, single-choice, a menu of instant-apply links), so a `belongs_to` filter over a large table stays usable. The count is taken per request, after a `collection:` callable resolves, so the control follows the data; declaring `as: :select` or `as: :combobox` pins it either way.
- Filters accept `url:` (plus `min_chars:` and `text:`), fetching their options from an endpoint as the user types rather than rendering a collection up front. Such a filter is always a combobox. Give `url:` as a callable so it resolves per request in the view (`-> { user_options_path }`); the endpoint is an ordinary host-app action including `Layered::Ui::ComboboxOptions`, so it is authorised however any index is. An active remote filter's values are labelled server-side from the records, so its tag reads "User: Alice" rather than "User: 12".

### Forms

- Record pickers: a field naming a `belongs_to`'s foreign key (`user_id`) renders as a single-select combobox over the associated records — a type-ahead input whose selection becomes a removable token — rather than as the raw number the column holds. Options default to `klass.all`, labelled the way a `belongs_to` filter's are and resolved per request; the picker posts the plain foreign key, so the write path is unchanged. `as:` opts out, `collection:` replaces the options, and every other combobox option passes through to `l_ui_combobox`. Polymorphic associations are skipped, having no single class to fill a picker.
- A field on a `belongs_to`'s foreign key takes its required flag from the association's `optional:` rather than from a presence validator on the column, since `belongs_to` validates the presence of the *association* under an `if:` that ActiveRecord attaches for its own reasons.

### Generators and i18n

- `layered:resource:scaffold`, `layered:resource`, `layered:resource:views`, `layered:resource:controller`, and `layered:resource:column` generators, plus `layered:resource:install_agent_skill` for the bundled agent skill.
- Flash messages are i18n-backed (`config/locales/en.yml`, key `layered.resource.flash.*`), overridable per-locale in the host app.

### Requirements

- Rails ~> 8.0, Ruby >= 3.3, and layered-ui-rails ~> 0.25 (>= 0.25.1, which is where the popover overflow fix the filter comboboxes depend on landed).
