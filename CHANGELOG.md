# Changelog

All notable changes to this project will be documented in this file. This project follows [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-04-19

Initial release.

### Added

- Routing DSL (`managed_resources`) that registers route-to-resource mappings with a `managed_` prefix and supports `only:` to restrict actions
- Generic `ResourcesController` that resolves the resource class at runtime and handles index, new, create, edit, update, and destroy
- `Layered::ManagedResource::Base` class for resource definitions with `model`, `columns`, `fields`, `search_fields`, `permitted_params`, `scope`, `build_record`, and `after_save_path`
- Auto-detection of required fields from model presence validations
- `link:` column option for linking index cells to nested managed resources
- Scope-aware route key generation for nested and multi-scope resource mounting
- Pluggable authentication via `managed_resource_before_action`
- Ransack-powered search and sorting on index views
- Pagy pagination with configurable `per_page` (default 15)
- `ManagedColumns` and `ManagedFields` concerns extracted from the controller
- Views built on `layered-ui-rails` helpers (`l_ui_table`, `l_ui_form`, `l_ui_search_form`, `l_ui_pagy`)
- Destroy with graceful handling of halted callbacks
- Route-definition-time validation of action combinations (e.g. `:new` requires `:index` and `:create`)
- Dummy app with Post and User models exercising full CRUD, readonly, deletable, and nested scopes
