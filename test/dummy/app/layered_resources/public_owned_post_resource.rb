class PublicOwnedPostResource < Layered::Resource::Base
  model Post

  columns [
    { attribute: :title, primary: true },
    { attribute: :body }
  ]

  fields [
    { attribute: :title },
    { attribute: :body, as: :text }
  ]

  owned_by :user, allow_nil: true
end
