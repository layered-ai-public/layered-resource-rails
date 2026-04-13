class UserResource < Layered::ManagedResource::Base
  model User

  columns [
    { attribute: :name, primary: true },
    { attribute: :email },
    { attribute: :posts_count, label: "Posts", link: :users_posts }
  ]

  search_fields [:name, :email]
end
