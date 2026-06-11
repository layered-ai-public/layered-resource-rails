class UserResource < Layered::Resource::Base
  model User

  columns [
    { attribute: :name, primary: true },
    { attribute: :email },
    { attribute: :posts_count, label: "Posts", link: :user_posts }
  ]

  root_breadcrumb "Home", "/"

  default_sort attribute: :name, direction: :asc

  fields [
    { attribute: :name },
    { attribute: :email }
  ]

  search_fields [:name, :email]

  search_placeholder "Search by name or email address"
end
