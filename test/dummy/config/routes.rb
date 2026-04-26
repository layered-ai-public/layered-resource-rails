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

  # Posts nested under users (scoped to that user)
  scope "users/:user_id" do
    layered_resources :posts
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

  scope "showonly" do
    layered_resources :posts, only: [:show]
  end
end
