class PunditPostResource < Layered::Resource::Base
  model Post

  columns [
    { attribute: :title, primary: true },
    { attribute: :body }
  ]

  fields [
    { attribute: :title },
    { attribute: :body, as: :text }
  ]

  use_pundit
  owned_by :user
end
