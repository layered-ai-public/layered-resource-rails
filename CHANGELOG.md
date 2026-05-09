# Changelog

All notable changes to this project will be documented in this file. This project follows [Semantic Versioning](https://semver.org/).

## Unreleased

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
