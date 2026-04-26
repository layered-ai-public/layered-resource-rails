# Changelog

All notable changes to this project will be documented in this file. This project follows [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-04-19

Initial release.

- `layered_resources` routing DSL with `only:` action restriction and scope-aware nesting
- `Layered::Resource::Base` for declaring `model`, `columns`, `fields`, `search_fields`, and `scope`
- Generic `ResourcesController` with index, new, create, edit, update, destroy
- Ransack search and sorting; Pagy pagination
- Pluggable authentication via `Layered::Resource.authentication_method`
