Rails.application.routes.draw do
  l_managed_resources :posts

  scope "/readonly" do
    l_managed_resources :posts, only: [:index]
  end

  scope "/deletable" do
    l_managed_resources :posts, only: %i[index destroy]
  end

  scope "/destroy-only" do
    l_managed_resources :posts, only: [:destroy]
  end
end
