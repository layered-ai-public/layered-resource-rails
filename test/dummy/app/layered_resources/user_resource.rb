class UserResource < Layered::Resource::Base
  model User

  columns [
    { attribute: :name, primary: true },
    { attribute: :email },
    { attribute: :posts_count, label: "Posts", link: :users_posts }
  ]

  fields [
    { attribute: :name },
    { attribute: :email }
  ]

  search_fields [:name, :email]
end
