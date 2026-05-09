module CustomNamespace
  class PostResource < Layered::Resource::Base
    model ::Post

    columns [
      { attribute: :title, primary: true }
    ]

    fields [
      { attribute: :title }
    ]
  end
end
