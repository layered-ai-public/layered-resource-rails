Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, path: "", path_names: { sign_in: "login", sign_up: "register", sign_out: "logout" }

  root "pages#home"

  get "home", to: "pages#home"
  get "examples", to: "pages#examples"

  # Users (index, edit, destroy)
  layered_resources :users, only: %i[index edit update destroy]

  scope "readonly" do
    layered_resources :users, only: [:index]
  end

  scope "deletable" do
    layered_resources :users, only: %i[index destroy]
  end

  # Standalone posts (all posts, no user scoping)
  layered_resources :posts

  # Posts nested under users (scoped to that user). Use Rails' own
  # `resources :users do` block so `polymorphic_path([@user, :posts])`
  # resolves naturally. `only: []` avoids generating duplicate routes
  # for users itself (already declared above via layered_resources).
  resources :users, only: [] do
    layered_resources :posts

    # Two-level deep nesting: comments under a user's post. Exercises
    # multi-parent breadcrumb / link generation (route key requires both
    # :user_id and :post_id).
    resources :posts, only: [] do
      layered_resources :comments
    end
  end

  scope "users/:user_id/readonly" do
    layered_resources :posts, only: [:index]
  end

  scope "users/:user_id/deletable" do
    layered_resources :posts, only: %i[index destroy]
  end

  scope "users/:user_id/admin" do
    layered_resources :posts, only: [:index]
  end

  # index + show, no edit: exercises the index primary-column link falling
  # back to the show page when the resource isn't editable.
  scope "detailonly" do
    layered_resources :posts, only: %i[index show]
  end

  scope "showonly" do
    layered_resources :posts, only: [:show]
  end

  # Surrounding `as:` is absorbed: helpers stay Rails-standard
  # (`new_manage_post_path`, not `manage_new_post_path`).
  scope path: "manage", as: "manage" do
    layered_resources :posts
  end

  scope "owned" do
    layered_resources :posts, resource: "OwnedPostResource"
  end

  scope "public_owned" do
    layered_resources :posts, resource: "PublicOwnedPostResource"
  end

  scope "pundit" do
    layered_resources :posts, resource: "PunditPostResource"
  end

  # Options endpoint backing RemotePostResource's remote author filter.
  resources :user_options, only: [:index]

  # Exercises a remote (`url:`) combobox filter (see RemotePostResource).
  scope "remote" do
    layered_resources :posts, resource: "RemotePostResource", only: [:index]
  end

  # Exercises a single-choice combobox filter (see SingleAuthorPostResource).
  scope "single_author" do
    layered_resources :posts, resource: "SingleAuthorPostResource", only: [:index]
  end

  # Exercises pinned filters + default values (see PinnedPostResource).
  scope "pinned" do
    layered_resources :posts, resource: "PinnedPostResource", only: [:index]
  end

  # Exercises explicit namespace: option. Derives CustomNamespace::PostResource
  # as the resource class and routes to CustomNamespace::ResourcesController
  # (which inherits from CustomNamespace::ApplicationController) automatically.
  # Path is explicit because we don't auto-infer from a `namespace :foo` block
  # (Rails composes URL helpers differently inside one — see routing.rb).
  scope "custom_namespace" do
    layered_resources :posts, namespace: "CustomNamespace"
  end

  scope "custom" do
    layered_resources :posts, controller: "custom_posts" do
      member do
        post :publish
        post :deferred
        get :state
      end
      collection do
        post :archive_all
        get :collection_state
      end
    end
  end
end
