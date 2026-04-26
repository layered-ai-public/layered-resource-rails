Layered Resource Rails Gem - Design Guidelines

Overview

This gem provides a declarative way to generate CRUD interfaces for models, while allowing a clean and gradual path to full customisation.

Core principle:

Stay declarative for structure, and hand over control for behaviour and presentation.

⸻

1. Where to Draw the Line

Keep in the DSL (Declarative)

These should feel like configuration, not programming:
	•	Field definitions (types, labels, validations)
	•	Basic associations
	•	Index / show / form structure
	•	CRUD actions
	•	Filtering, sorting, pagination
	•	Policy integration
	•	Simple hooks (before/after actions)

Example:

class PostResource < Layered::Resource::Base
  model Post

  columns [
    { attribute: :title, primary: true },
    { attribute: :author },
    { attribute: :published_at }
  ]

  fields [
    { attribute: :title },
    { attribute: :published_at, as: :datetime },
    { attribute: :author_id, as: :belongs_to }
  ]
end


⸻

Move to Custom Code

Do not attempt to support these in the DSL:
	•	Complex UI logic (dynamic forms, multi-step flows)
	•	Heavy JavaScript interactions
	•	Custom layouts (dashboards, wizards)
	•	Business workflows (approval flows, state machines)
	•	Highly tailored styling

These should trigger ejection or override, not more DSL.

⸻

2. Views - Progressive Customisation

Stage 1 - Fully Managed

layered_resources :posts

	•	No generated files
	•	Uses gem-provided views
	•	Convention over configuration

⸻

Stage 2 - Partial Override

layered_resources :posts do
  override :form
  override :index_row
end

Convention:

app/views/layered/posts/_form.html.erb

Fallback to gem defaults if not present.

⸻

Stage 3 - Full Ejection (Generator)

rails g layered_resource:install posts

Generates:

app/views/layered/posts/
  index.html.erb
  show.html.erb
  _form.html.erb
  _fields/
    _string.html.erb
    _datetime.html.erb
    _association.html.erb

Use UI kit helpers:

<%= ui.form do %>
  <%= ui.input :title %>
  <%= ui.datetime :published_at %>
<% end %>


⸻

View Resolution Strategy
	•	If custom view exists -> use it
	•	Otherwise -> fallback to gem

⸻

3. Controllers - Design Strategy

Base Controller (Gem)

A single generic controller handles all resources:

Layered::Resource::ResourcesController

Responsibilities:
	•	CRUD actions
	•	Resource loading
	•	Strong params
	•	Rendering views
	•	Basic querying
	•	Hook execution

Example:

class Layered::Resource::ResourcesController < ApplicationController
  before_action :load_resource_definition
  before_action :set_record, only: %i[show edit update destroy]

  def index
    @records = scope.all
  end

  def create
    @record = model.new(permitted_params)
    if @record.save
      redirect_to ...
    else
      render :new
    end
  end

  private

  def model
    @resource.model
  end

  def permitted_params
    params.require(resource_name).permit(@resource.permitted_params)
  end
end


⸻

Controller Boundaries

Keep in the Gem
	•	CRUD logic
	•	Parameter handling
	•	Basic querying
	•	Standard responses

Do NOT Support
	•	Complex workflows
	•	Business logic
	•	Custom endpoints
	•	Non-CRUD behaviour

⸻

4. Controller Customisation Model

Stage 1 - Fully Managed

layered_resources :posts

Uses base controller internally.

⸻

Stage 2 - Extend via Inheritance (Recommended)

class PostsController < Layered::Resource::ResourcesController
  private

  def scope
    super.published
  end

  def after_create(record)
    NotifyJob.perform_later(record)
  end
end

Routes:

layered_resources :posts, controller: "posts"


⸻

Stage 3 - Full Ejection

rails g layered_resource:controller posts

Generates:

class PostsController < ApplicationController
  def index
    @posts = Post.all
  end
end

Routes:

resources :posts

No dependency on the gem remains.

⸻

5. Routing Strategy

layered_resources :posts

Internally routes to base controller.

Optional override:

layered_resources :posts, controller: "posts"

Implicit behaviour:
	•	If custom controller exists -> use it
	•	Otherwise -> fallback to base controller

⸻

6. Key Design Principles

Always Allow Exit
	•	Ejection must be clean and safe
	•	No hidden coupling
	•	Generated code should be idiomatic Rails

⸻

Avoid Half Magic

Make behaviour explicit:

[Layered::Resource] Using PostsController (custom)
[Layered::Resource] Using layered view: posts/form


⸻

Prefer Ruby Over DSL for Behaviour

Avoid DSL-heavy behaviour configuration.

Prefer plain Ruby overrides and inheritance.

⸻

Composition Over Configuration

Avoid overloading field options.

Prefer view/component overrides.

⸻

Stable, Boring Base Controller
	•	Predictable
	•	Minimal magic
	•	Easy to extend
	•	Easy to replace

⸻

7. Mental Model

Admin panel until proven otherwise.
	•	Start fully managed
	•	Override selectively
	•	Eject when necessary

⸻

8. What Success Looks Like
	•	Beginners build CRUD instantly
	•	Intermediate users override small pieces
	•	Advanced users eject cleanly
	•	The gem stays small and maintainable
