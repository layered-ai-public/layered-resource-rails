# layered-resource-rails

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Website](https://img.shields.io/badge/Website-layered.ai-purple)](https://www.layered.ai/)
[![GitHub](https://img.shields.io/badge/GitHub-layered--resource--rails-black)](https://github.com/layered-ai-public/layered-resource-rails)
[![Discord](https://img.shields.io/badge/Discord-join-5865F2)](https://discord.gg/aCGqz9Bx)
[![YouTube](https://img.shields.io/badge/YouTube-subscribe-FF0000)](https://www.youtube.com/@UseLayeredAi)
[![X](https://img.shields.io/badge/X-follow-000000)](https://x.com/UseLayeredAi)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-follow-0A66C2)](https://www.linkedin.com/company/uselayeredai/)

An open source, Rails 8+ engine that provides convention-over-configuration CRUD scaffolding. Define a resource class and a single route, and you get index, show, new/create, edit/update, and destroy actions with search and pagination. Built on top of [layered-ui-rails](https://github.com/layered-ai-public/layered-ui-rails), Ransack, and Pagy.

## Why use it

Most Rails apps need an admin area, an internal dashboard, or a "list and edit some records" screen long before they need anything bespoke. `layered-resource-rails` gets you there in a few lines, then stays out of your way as your needs grow:

- **Skip the boilerplate.** Declare your columns, fields, and search - get index, show, forms, search, sort, and pagination for free. No scaffold to maintain, no half-finished admin gem to fight.
- **Looks right out of the box.** Tables, forms, and pagination come pre-styled via [layered-ui-rails](https://github.com/layered-ai-public/layered-ui-rails) with WCAG 2.2 AA compliance and dark mode included.
- **Override only what you need.** Swap a single view partial, subclass the controller for a custom scope or redirect, or generate plain ERB to take full control - without rewriting the rest.
- **Eject cleanly when you outgrow it.** Generate a standard Rails controller and views, drop the gem, and you're left with idiomatic Rails. No lock-in, no hidden coupling.

## Requirements

- Ruby on Rails >= 8.0
- [layered-ui-rails](https://github.com/layered-ai-public/layered-ui-rails) >= 0.9
- Ransack >= 4.0
- Pagy >= 43.2

## Getting started

Add to your Gemfile and install:

```bash
bundle add layered-resource-rails
```

`layered-resource-rails` depends on `layered-ui-rails` for its UI. If you haven't already set it up, run its install generator:

```bash
bin/rails generate layered:ui:install
```

## Quick start

### 1. Define a resource

Create a file at `app/layered_resources/post_resource.rb`:

```ruby
class PostResource < Layered::Resource::Base
  model Post

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

### 2. Add the route

In `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  layered_resources :posts
end
```

That's it. You now have a full CRUD interface with search and pagination for `Post`.

### What you get

| Route                   | Action  | Description      |
|-------------------------|---------|------------------|
| `GET /posts`            | index   | Paginated table  |
| `GET /posts/:id`        | show    | Post detail page |
| `GET /posts/new`        | new     | New post form    |
| `POST /posts`           | create  | Create post      |
| `GET /posts/:id/edit`   | edit    | Edit post form   |
| `PATCH /posts/:id`      | update  | Update post      |
| `DELETE /posts/:id`     | destroy | Delete post      |

When `:show` is enabled, the index table's primary column (`primary: true`, or the first column) is automatically linked to the show page.

## Options

**Read-only (no forms):** omit `fields` and restrict routes:

```ruby
class PostResource < Layered::Resource::Base
  model Post

  columns [
    { attribute: :title, primary: true },
    { attribute: :created_at, label: "Published" }
  ]
end
```

```ruby
layered_resources :posts, only: [:index]
```

**Restrict actions:**

```ruby
layered_resources :posts, only: [:index, :show, :edit, :update]
```

**Custom scope (e.g. tenant isolation):**

```ruby
class PostResource < Layered::Resource::Base
  model Post

  # ...columns, fields, etc.

  def self.scope(controller)
    controller.current_team.posts
  end
end
```

## Associations

Resources are independent - each model gets its own resource class. To surface association data on an index, add a virtual column whose `attribute:` is a method on the model. For `Post belongs_to :user`, expose `user.name` by delegating on the model:

```ruby
class Post < ApplicationRecord
  belongs_to :user
  delegate :name, to: :user, prefix: true, allow_nil: true # post.user_name
end
```

```ruby
class PostResource < Layered::Resource::Base
  model Post

  columns [
    { attribute: :title, primary: true },
    { attribute: :user_name, label: "Author" },
    { attribute: :created_at, label: "Published" }
  ]
end
```

### Nested routes

To scope posts to a user (`/users/:user_id/posts`), nest the route and resolve the parent in `scope`:

```ruby
# config/routes.rb
layered_resources :users
scope "users/:user_id" do
  layered_resources :posts
end
```

```ruby
class PostResource < Layered::Resource::Base
  model Post

  # ...columns, fields, etc.

  def self.scope(controller)
    if controller.params[:user_id].present?
      User.find(controller.params[:user_id]).posts
    else
      Post.all
    end
  end
end
```

### Linking columns to a nested index

A column on the parent can link to its children's index using `link:` with the nested route's key:

```ruby
class UserResource < Layered::Resource::Base
  model User

  columns [
    { attribute: :name, primary: true },
    { attribute: :email },
    { attribute: :posts_count, label: "Posts", link: :users_posts }
  ]
end
```

The `posts_count` cell on each user row renders as a badge linked to `/users/:id/posts`.

## Variants via inheritance

For variants that warrant their own URL - typically a separate admin area - declare a subclass and register it on its own route. The subclass inherits `model`, `columns`, `fields`, `search_fields`, `default_sort`, and `per_page` from the parent and overrides only what differs:

```ruby
# app/layered_resources/admin/post_resource.rb
class Admin::PostResource < PostResource
  columns [
    { attribute: :title, primary: true },
    { attribute: :status },
    { attribute: :author_name, label: "Author" },
    { attribute: :created_at, label: "Published" }
  ]

  fields [
    { attribute: :title },
    { attribute: :body, as: :text },
    { attribute: :status },
    { attribute: :pinned, as: :checkbox }
  ]
end
```

```ruby
# config/routes.rb
layered_resources :posts
namespace :admin do
  layered_resources :posts, resource: "Admin::PostResource"
end
```

`search_fields` and `model` aren't redeclared - they're inherited from `PostResource`.

## Authentication

`Layered::Resource::ResourcesController` inherits from your app's `ApplicationController`, so any `before_action` you've declared there (e.g. Devise's `authenticate_user!`) already protects every layered resource request.

## Escape hatching

The gem is designed so you can start fully managed and progressively take over control if you outgrow the defaults.

**Override the scope or redirect target** directly in the resource class:

```ruby
class PostResource < Layered::Resource::Base
  model Post

  # ...columns, fields, etc.

  def self.scope(controller)
    controller.current_team.posts
  end

  def self.build_record(controller)
    scope(controller).build(author: controller.current_user)
  end

  def self.after_save_path(controller, record)
    controller.main_app.post_path(record)
  end
end
```

**Eject views** when you need full control over presentation:

```
rails g layered:resource:views posts
```

This copies the gem's actual `index`, `show`, `new`, and `edit` templates into `app/views/layered/posts/` - fully populated, working ERB you can edit immediately. Delete any of them to fall back to the gem default; keep the rest to override only what you need.

**Override the controller.** Use the generator to create one in the right place:

```
rails g layered:resource:controller posts
```

This gives you a controller that inherits from the base - override any of the standard CRUD actions and call `super` when you only want to tweak behaviour.

If you outgrow the gem entirely, drop the inheritance and write a plain Rails controller:

```ruby
class PostsController < ApplicationController
  def index
    @posts = Post.all
  end

  # ...
end
```

```ruby
# swap the route
resources :posts
```

## Documentation

Run the included dummy app locally to explore:

```bash
git clone https://github.com/layered-ai-public/layered-resource-rails.git
cd layered-resource-rails
bundle install
cd test/dummy && bin/rails db:setup && bin/dev
```

## Contributing

This project is still in its early days. We welcome issues, feedback, and ideas - they genuinely help shape the direction of the project. That said, we're holding off on accepting pull requests for now to stay focused on getting the foundations right. Thank you for your patience and interest. See [CLA.md](CLA.md) for the full policy.

## License

Released under the [Apache 2.0 License](LICENSE).

Copyright 2026 LAYERED AI LIMITED (UK company number: 17056830). See [NOTICE](NOTICE) for attribution details.

## Trademarks

The source code is fully open, but the layered.ai name, logo, and brand assets are trademarks of LAYERED AI LIMITED. The Apache 2.0 license does not grant rights to use the layered.ai branding. Forks and redistributions must use a distinct name. See [TRADEMARK.md](TRADEMARK.md) for the full policy.
