Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, path: "", path_names: { sign_in: "login", sign_up: "register", sign_out: "logout" }

  root "pages#welcome"

  get "welcome", to: "pages#welcome"

  l_managed_resources :posts

  scope "/readonly" do
    l_managed_resources :posts, only: [:index]
  end

  scope "/deletable" do
    l_managed_resources :posts, only: %i[index destroy]
  end

  scope "/admin" do
    l_managed_resources :posts, only: [:index]
  end
end
