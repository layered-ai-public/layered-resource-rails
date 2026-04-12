# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Rails Engine gem (`layered-managed-resource-rails`) that provides convention-over-configuration CRUD scaffolding for Rails 8+. It auto-generates index, new/create, edit/update, and destroy interfaces using a single routing DSL method (`l_managed_resources`) and model-level configuration via the `Layered::ManagedResource::Resource` concern. Built on top of `layered-ui-rails` for UI components, Ransack for search, and Pagy for pagination.

## Commands

```bash
# Install dependencies (requires sibling ../layered-ui-rails checkout for local dev)
bundle install

# Run full test suite
bundle exec rake test

# Run a single test file
bundle exec ruby -Itest test/integration/managed_resource_crud_test.rb

# Run a single test by name
bundle exec ruby -Itest test/integration/managed_resource_crud_test.rb -n "test_index_renders_with_new_link_when_crud_enabled"
```

## Architecture

### Engine Structure

The gem is a Rails Engine isolated under `Layered::ManagedResource`. It works through three cooperating layers:

1. **Routing DSL** (`lib/layered/managed_resource/routing.rb`) — `l_managed_resources :resource_name` is mixed into `ActionDispatch::Routing::Mapper`. It registers route-to-model mappings in a thread-safe `Concurrent::Map` registry and generates named routes with a `managed_` prefix. Supports `only:` to restrict actions, `model:` to override the inferred class, and scope-aware route key generation.

2. **Generic Controller** (`app/controllers/layered/managed_resource/resources_controller.rb`) — A single `ResourcesController` handles all managed resources. It resolves which model to use at runtime via the `_managed_route_key` route default, then delegates to model-level class methods for scoping, column definitions, field definitions, and permitted params.

3. **Model Concern** (`app/models/concerns/layered/managed_resource/resource.rb`) — `Layered::ManagedResource::Resource` is included in ActiveRecord models. It provides overridable class methods that the controller calls:
   - `l_managed_resource_columns` — columns displayed on the index table
   - `l_managed_resource_fields` — form fields for new/edit (empty = read-only, no CRUD forms)
   - `l_managed_resource_search_fields` — Ransack search attributes
   - `l_managed_resource_permitted_params` — derived from fields by default
   - `l_managed_resource_scope(controller)` — default scope (override for tenant isolation)
   - `l_managed_resource_build_record(controller)` — how to instantiate new records
   - `l_managed_resource_after_save_path(controller, record)` — redirect target after create/update/destroy

### Key Design Decisions

- The routing layer validates action combinations at route-definition time (e.g., `:new` requires `:index` and `:create`).
- `l_managed_resource_fields` returning empty disables all CRUD forms; `:destroy` still works independently.
- Views use `layered-ui-rails` helpers (`l_ui_table`, `l_ui_form`, `l_ui_search_form`, `l_ui_pagy`) — not standard Rails form builders.
- Authentication is pluggable via `Layered::ManagedResource.l_managed_resource_before_action`, which names a controller method to call as a before_action.

### Test Setup

Tests use a dummy Rails app at `test/dummy/` with SQLite. The dummy app has `Post` and `User` models and multiple route scopes (full CRUD, readonly, deletable, destroy-only) to exercise the `only:` option.

## Dependencies

- `layered-ui-rails ~> 0.3` — UI component library (local path override in Gemfile for development)
- `ransack ~> 4.0` — search/filtering
- `pagy ~> 43.2` — pagination
- `rails ~> 8.0`
