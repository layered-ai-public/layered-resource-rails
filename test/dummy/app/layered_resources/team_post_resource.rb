# Posts with row actions that vary per record and per signed-in user, from
# app/views/layered/team_posts/_row_actions.html.erb: the author gets Edit
# and Delete, everyone else a link to the author's other posts, and only
# posts with comments get a Comments link.
class TeamPostResource < Layered::Resource::Base
  model Post

  columns [
    { attribute: :title, primary: true },
    { attribute: :user_name, label: "Author" },
    { attribute: :comments_count, label: "Comments", as: :badge, rounded: true }
  ]

  search_fields [:title]

  fields [
    { attribute: :title },
    { attribute: :body, as: :text },
    { attribute: :user_id, label: "Author" }
  ]

  # The Author column and the row menu both read each post's user.
  def self.scope(controller)
    super.includes(:user)
  end
end
