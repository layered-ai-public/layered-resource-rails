# Quick Start Example

## 1. Define a resource

Create a file at `app/layered_resources/article_resource.rb`:

```ruby
class ArticleResource < Layered::Resource::Base
  model Article

  columns [
    { attribute: :title, primary: true },
    { attribute: :status },
    { attribute: :created_at, label: "Published" }
  ]

  search_fields [:title]

  default_sort attribute: :created_at, direction: :desc

  fields [
    { attribute: :title },
    { attribute: :body, as: :text },
    { attribute: :status }
  ]
end
```

## 2. Add the route

In `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  layered_resources :articles
end
```

That's it. You now have a full CRUD interface with search and pagination for `Article`.

## What you get

| Route                      | Action  | Description        |
|----------------------------|---------|--------------------|
| `GET /articles`            | index   | Paginated table    |
| `GET /articles/new`        | new     | New article form   |
| `POST /articles`           | create  | Create article     |
| `GET /articles/:id/edit`   | edit    | Edit article form  |
| `PATCH /articles/:id`      | update  | Update article     |
| `DELETE /articles/:id`     | destroy | Delete article     |

## Options

**Read-only (no forms):** omit `fields` and restrict routes:

```ruby
class ArticleResource < Layered::Resource::Base
  model Article

  columns [
    { attribute: :title, primary: true },
    { attribute: :created_at, label: "Published" }
  ]
end
```

```ruby
layered_resources :articles, only: [:index]
```

**Restrict actions:**

```ruby
layered_resources :articles, only: [:index, :edit, :update]
```

**Custom scope (e.g. tenant isolation):**

```ruby
class ArticleResource < Layered::Resource::Base
  model Article

  # ...columns, fields, etc.

  def self.scope(controller)
    controller.current_team.articles
  end
end
```

## Authentication

Protect all layered resources with a single initializer setting. Point it at any controller method (e.g. Devise's `authenticate_user!`):

```ruby
# config/initializers/layered_resource.rb
Layered::Resource.authentication_method = :authenticate_user!
```

This runs as a `before_action` on every layered resource request. No per-resource configuration needed.

## Escape hatching

The gem is designed so you can start fully managed and progressively take over control if you outgrow the defaults.

**Override the scope or redirect target** directly in the resource class:

```ruby
class ArticleResource < Layered::Resource::Base
  model Article

  # ...columns, fields, etc.

  def self.scope(controller)
    controller.current_team.articles
  end

  def self.build_record(controller)
    scope(controller).build(author: controller.current_user)
  end

  def self.after_save_path(controller, record)
    controller.main_app.article_path(record)
  end
end
```

**Eject views** when you need full control over presentation:

```
rails g layered_resource:views articles
```

This generates standard ERB templates into `app/views/layered/articles/` that you own entirely. The gem falls back to its defaults for any view you haven't overridden.

**Override the controller.** Use the generator to create one in the right place:

```
rails g layered:resource:controller articles
```

This gives you a controller that inherits from the base -- override just what you need:

```ruby
class ArticlesController < Layered::Resource::ResourcesController
  private

  def scope
    super.published
  end

  def after_create(record)
    NotifyJob.perform_later(record)
  end
end
```

If you outgrow the gem entirely, drop the inheritance and write a plain Rails controller:

```ruby
class ArticlesController < ApplicationController
  def index
    @articles = Article.all
  end

  # ...
end
```

```ruby
# swap the route
resources :articles
```
