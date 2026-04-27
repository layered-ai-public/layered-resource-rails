# Changelog

All notable changes to this project will be documented in this file. This project follows [Semantic Versioning](https://semver.org/).

## Unreleased

- `:show` action: `GET /:id` renders a record detail page using the resource's columns
- Index tables auto-link the primary column to the show page when `:show` is enabled
- View escape hatch: drop a template at `app/views/layered/<resource_name>/<action>.html.erb` (or partial like `_form`) to override the gem default for that resource
- `rails g layered:resource:views <name>` generator copies the gem's view templates into `app/views/layered/<name>/` for full customisation

## [0.1.0] - 2026-04-19

Initial release.

- `layered_resources` routing DSL with `only:` action restriction and scope-aware nesting
- `Layered::Resource::Base` for declaring `model`, `columns`, `fields`, `search_fields`, and `scope`
- Generic `ResourcesController` with index, new, create, edit, update, destroy
- Ransack search and sorting; Pagy pagination
- Pluggable authentication via `Layered::Resource.authentication_method`
