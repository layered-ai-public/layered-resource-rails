Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, path: "", path_names: { sign_in: "login", sign_up: "register", sign_out: "logout" }

  root "pages#welcome"

  get "welcome", to: "pages#welcome"

  # Standalone posts (all posts, no user scoping)
  managed_resources :posts

  # Posts nested under users (scoped to that user)
  scope "users/:user_id" do
    managed_resources :posts
  end

  scope "users/:user_id/readonly" do
    managed_resources :posts, only: [:index]
  end

  scope "users/:user_id/deletable" do
    managed_resources :posts, only: %i[index destroy]
  end

  scope "users/:user_id/admin" do
    managed_resources :posts, only: [:index]
  end
end
