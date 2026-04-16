class PostResource < Layered::ManagedResource::Base
  model Post

  columns [
    { attribute: :title, primary: true },
    { attribute: :body },
    { attribute: :user_name, label: "Owner" },
    { attribute: :created_at, label: "Created" }
  ]

  search_fields [:title, :body]

  default_sort attribute: :created_at, direction: :desc

  fields [
    { attribute: :title },
    { attribute: :body, as: :text },
    { attribute: :created_at, as: :datetime }
  ]

  def self.scope(controller)
    if controller.params[:user_id].present?
      User.find(controller.params[:user_id]).posts
    else
      Post.all
    end
  end

  def self.build_record(controller)
    scope(controller).build
  end
end
