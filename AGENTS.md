# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

A Rails 8+ engine providing CRUD scaffolding. Consumer apps declare a `Layered::Resource::Base` subclass in `app/layered_resources/` and a `layered_resources :name` route. README is the user-facing API reference.

## Commands

```bash
bundle exec rake test                                              # full suite
bundle exec rake test TEST=test/integration/layered_resource_crud_test.rb
cd test/dummy && bin/dev                                           # manual exploration
```

## Architecture

Three load-bearing pieces:

- **`Layered::Resource::Base`** (`lib/layered/resource/base.rb`) - DSL (`model`, `columns`, `fields`, `search_fields`, `default_sort`, `per_page`) plus override points (`scope`, `build_record`, `after_save_path`). `inherited_attribute` walks the ancestor chain manually because class ivars aren't Ruby-inherited - this enables resource subclassing. `configure_ransack` patches `ransackable_attributes`/`ransackable_associations` on the model but **only responds when called with the resource class as `auth_object`**; other callers fall through to the original methods, preserving host-app config.

- **`Layered::Resource::Routing`** (`lib/layered/resource/routing.rb`) - the `layered_resources` route DSL plus a process-wide `Concurrent::Map` registry. Each route bakes a `_layered_resource_route_key` default into `path_parameters` so the controller can look up the right resource. Parses surrounding `scope` paths at registration time for nested-route support. Raises early on incoherent `only:` combos (e.g. `:new` without `:create`) - keep those guards in sync if adding actions.

- **`Layered::Resource::ResourcesController`** (`app/controllers/layered/resource/resources_controller.rb`) - inherits from the **host app's** `ApplicationController`, so its `before_action`s (e.g. Devise) apply automatically. `load_layered_resource` reads the route key, looks up the resource, and sets the `@can_*` action flags. `_prefixes` is overridden so `app/views/layered/<name>/` overrides win - this is what makes `rails g layered:resource:views` ejection work.

Engine (`lib/layered/resource/engine.rb`) autoloads `app/layered_resources`, mixes `Routing` into `Mapper`, includes `Pagy::Method`, and prepends the engine view path.

## Notes

- Tests in `test/integration/` run against `test/dummy/` (a real Rails app with `Post` and `User` models, plus `PostResource` and `UserResource`). Integration tests are the contract for controller/routing/DSL changes.
- `attribute_required?` treats a field as required only when the presence validator is unconditional - don't tighten without considering conditional-validation forms.
- `concurrent-ruby` is depended on solely for the routing registry's `Concurrent::Map`.
