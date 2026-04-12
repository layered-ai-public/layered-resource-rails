class PostResource < Layered::ManagedResource::Base
  model Post

  columns [
    { attribute: :title, primary: true },
    { attribute: :body },
    { attribute: :created_at, label: "Created" }
  ]

  search_fields [:title, :body]

  default_sort attribute: :created_at, direction: :desc

  fields [
    { attribute: :title, required: true },
    { attribute: :body, as: :text },
    { attribute: :user_id, as: :select, label: "Author", collection: -> { User.pluck(:email, :id) } }
  ]
end
