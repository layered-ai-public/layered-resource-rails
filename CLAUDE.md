# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Rails Engine gem (`layered-resource-rails`) that provides convention-over-configuration CRUD scaffolding for Rails 8+. It auto-generates index, show, new/create, edit/update, and destroy interfaces using a single routing DSL method (`layered_resources`) and separate resource definition classes that inherit from `Layered::Resource::Base`. Built on top of `layered-ui-rails` for UI components, Ransack for search, and Pagy for pagination.

## Commands

```bash
# Install dependencies (requires sibling ../layered-ui-rails checkout for local dev)
bundle install

# Run full test suite
bundle exec rake test

# Run a single test file
bundle exec ruby -Itest test/integration/layered_resource_crud_test.rb

# Run a single test by name
bundle exec ruby -Itest test/integration/layered_resource_crud_test.rb -n "test_index_renders_with_new_link_when_crud_enabled"
```

## Architecture

### Engine Structure

The gem is a Rails Engine isolated under `Layered::Resource`. It works through three cooperating layers:

1. **Routing DSL** (`lib/layered/resource/routing.rb`) - `layered_resources :resource_name` is mixed into `ActionDispatch::Routing::Mapper`. It registers route-to-resource mappings in a thread-safe `Concurrent::Map` registry and generates named routes with a `layered_` prefix. Supports `only:` to restrict actions, `resource:` to override the inferred resource class, and scope-aware route key generation.

2. **Generic Controller** (`app/controllers/layered/resource/resources_controller.rb`) - A single `ResourcesController` handles all layered resources. It resolves which resource class to use at runtime via the `_layered_resource_route_key` route default, then delegates to the resource class for scoping, column definitions, field definitions, and permitted params.

3. **Resource Definition** (`lib/layered/resource/base.rb`) - `Layered::Resource::Base` is the base class for resource definitions. Users create subclasses in `app/layered_resources/` (e.g., `PostResource`) that configure:
   - `model` - the ActiveRecord model class (inferred from resource class name by default)
   - `columns` - columns displayed on the index table
   - `fields` - form fields for new/edit (empty = read-only, no CRUD forms)
   - `search_fields` - Ransack search attributes
   - `permitted_params` - derived from fields by default
   - `scope(controller)` - default scope (override for tenant isolation)
   - `build_record(controller)` - how to instantiate new records
   - `after_save_path(controller, record)` - redirect target after create/update/destroy

### Key Design Decisions

- The routing layer validates action combinations at route-definition time (e.g., `:new` requires `:index` and `:create`). `:show` has no dependencies and can stand alone.
- `fields` returning empty disables all CRUD forms; `:show` and `:destroy` still work independently.
- When `:show` is enabled, the index table's primary column (the one with `primary: true`, or the first column) is auto-linked to the show page. Columns that already declare a custom `link:` are left alone.
- Views use `layered-ui-rails` helpers (`l_ui_table`, `l_ui_form`, `l_ui_search_form`, `l_ui_pagy`) - not standard Rails form builders.
- Authentication piggybacks on the host app's `ApplicationController` — `ResourcesController` inherits from it, so any `before_action` declared there already runs.
- Resource classes live in `app/layered_resources/` (autoloaded by the engine) and keep models clean of admin/UI concerns.

### Test Setup

Tests use a dummy Rails app at `test/dummy/` with SQLite. The dummy app has `Post` and `User` models, a `PostResource` definition, and multiple route scopes (full CRUD, readonly, deletable, destroy-only) to exercise the `only:` option.

## Design Guidelines

See `GUIDELINES.md` for the design philosophy: progressive customisation (fully managed → partial override → full ejection), controller extension model, and what belongs in the DSL vs. custom code.

## Dependencies

- `layered-ui-rails ~> 0.8` - UI component library (local path override in Gemfile for development)
- `ransack ~> 4.0` - search/filtering
- `pagy ~> 43.2` - pagination
- `rails ~> 8.0`
