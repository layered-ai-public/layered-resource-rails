# Changelog

All notable changes to this project will be documented in this file. This project follows [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-04-28

Initial release.

- `Layered::Resource::Base` DSL: `model`, `columns`, `fields`, `search_fields`, `default_sort`, `per_page`.
- `layered_resources` route helper with full CRUD, plus `only:`/`except:` to restrict actions.
- Index search, sort, and pagination via Ransack and Pagy.
- Resource inheritance for namespaced variants (e.g. `Admin::PostResource`).
- Escape hatches: `scope`, `build_record`, `after_save_path`, plus `layered:resource`, `layered:resource:views`, and `layered:resource:controller` generators.
- Auth inherited from the host app's `ApplicationController`.
