class CommentResource < Layered::Resource::Base
  model Comment

  columns [
    { attribute: :body, primary: true },
    { attribute: :created_at, label: "Created" }
  ]

  search_fields [:body]

  default_sort attribute: :created_at, direction: :desc

  fields [
    { attribute: :body, as: :text }
  ]

  def self.scope(controller)
    Post.find(controller.params[:post_id]).comments
  end

  def self.build_record(controller)
    scope(controller).build
  end
end
