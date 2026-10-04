# Posts addressed by their `uid` token rather than their id, the way records
# whose ids shouldn't be guessable are. `lookup_attribute :uid` makes every
# member URL - edit, show, destroy, and the comments nested beneath - carry
# the uid, and looks the record up by it. The title links to the post's show
# page rather than its edit form: `link: false` leaves the primary column to
# its own `render:` proc.
class ArticleResource < Layered::Resource::Base
  model Post

  lookup_attribute :uid

  columns [
    { attribute: :title, primary: true, link: false,
      render: ->(record, view) { view.link_to(record.title, view.article_path(record.uid), data: { turbo_frame: "_top" }) } },
    { attribute: :comments_count, label: "Comments", as: :badge, rounded: true, link: :article_comments },
    { attribute: :created_at, label: "Created" }
  ]

  search_fields [:title]

  default_sort attribute: :created_at, direction: :desc

  fields [
    { attribute: :title },
    { attribute: :body, as: :text },
    { attribute: :user_id, label: "Author" }
  ]
end
