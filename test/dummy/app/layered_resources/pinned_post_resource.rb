# Exercises pinned filters and default values: every filter is pinned (so no
# "Add filter" button renders) and status defaults to published unless the
# request carries its own status state (including an explicit blank clear).
class PinnedPostResource < Layered::Resource::Base
  model Post

  columns [
    { attribute: :title, primary: true },
    { attribute: :status }
  ]

  filters status: { pinned: true, default: Post.statuses[:published] },
          featured: { pinned: true }
end
