# Changelog

All notable changes to this project will be documented in this file. This project follows [Semantic Versioning](https://semver.org/).

## Unreleased

- `filters :status, :created_at, user: { multiple: true }` — structured index filters rendered as an "Add filter" popover plus removable chips (picking a filter adds an unset chip to the end of the row; its popover holds the controls, its ✕ removes it). Control and Ransack predicate are inferred from the column type (enum/`belongs_to` → multi-select via `_in` — pass `multiple: false` for single-choice `_eq`, boolean → Yes/No, date/datetime → date range, numeric → number range, string → contains); override per attribute with `as:`/`collection:`/`multiple:`/`label:`/`pinned:`/`default:`. Pinned filters render as always-shown chips (no ✕, never in the add menu — which disappears entirely once every filter is pinned); a default applies when the request carries no state for the filter, and clearing writes an explicit blank so it doesn't re-apply. Filters, search, and sort round-trip each other as hidden fields, so they compose in the URL with no JavaScript.
- `layered_resources :foo, namespace: "Foo::Bar"` derives the resource class as `Foo::Bar::FooResource` and routes to `Foo::Bar::ResourcesController` when defined — replaces the old three-line `resource:`/`controller:` plumbing for engine mounts.
- Extracted `Layered::Resource::Controller` concern. Engines can define their own `<Namespace>::ResourcesController` inheriting from their own `ApplicationController` and `include Layered::Resource::Controller` to keep auth/authorize before_actions wired correctly.
- `destroy` rescues `ActiveRecord::InvalidForeignKey` and `ActiveRecord::DeleteRestrictionError`, redirecting to the index with a flash instead of 500ing.
- Flash messages move to i18n (`config/locales/en.yml`, key `layered.resource.flash.*`). Override per-locale in the host app.
- `owned_by` raises `Layered::Resource::MissingOwnerError` when `via` returns nil — surfaces auth misconfiguration loudly instead of silently 404ing every request. Pass `allow_nil: true` to opt into public-with-scope behaviour. (No-op when `use_pundit` is enabled — Pundit handles the policy gate.)

## [0.1.0] - 2026-04-28

Initial release.

- `Layered::Resource::Base` DSL: `model`, `columns`, `fields`, `search_fields`, `default_sort`, `per_page`.
- `layered_resources` route helper with full CRUD, plus `only:`/`except:` to restrict actions.
- Index search, sort, and pagination via Ransack and Pagy.
- Resource inheritance for namespaced variants (e.g. `Admin::PostResource`).
- Escape hatches: `scope`, `build_record`, `after_save_path`, plus `layered:resource`, `layered:resource:views`, and `layered:resource:controller` generators.
- Auth inherited from the host app's `ApplicationController`.
