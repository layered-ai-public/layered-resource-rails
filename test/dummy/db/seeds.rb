# Users
users = [
  { name: "Test User", email: "test.user@example.com" },
  { name: "Alice", email: "alice@example.com" },
  { name: "Bob", email: "bob@example.com" },
  { name: "Charlie", email: "charlie@example.com" }
].map do |attrs|
  User.find_or_create_by!(email: attrs[:email]) do |u|
    u.name = attrs[:name]
    u.password = "notasecret123"
    u.password_confirmation = "notasecret123"
    u.confirmed_at = Time.now
  end
end

# More users than Layered::Resource.filter_combobox_threshold (10), so the
# PostResource author filter crosses it and renders as a type-ahead combobox
# rather than a checkbox list — the switch is worth seeing in bin/dev. Posts
# stay with the four named users above.
%w[Dana Eve Frank Grace Heidi Ivan Judy Karl].each do |name|
  User.find_or_create_by!(email: "#{name.downcase}@example.com") do |u|
    u.name = name
    u.password = "notasecret123"
    u.password_confirmation = "notasecret123"
    u.confirmed_at = Time.now
  end
end

# Posts. Body is required, so it is assigned outside the create block as well:
# re-seeding a database whose posts predate that validation repairs them rather
# than leaving rows that no longer validate.
#
# A few paragraphs each, so a post's show page (see
# app/views/layered/articles/show.html.erb) has something to show.
paragraphs = [
  "Resources are declared once and mounted with a single route. The index, forms and show page all come from that one class, so a new screen is a few lines rather than a controller, a set of views and the tests to go with them.",
  "Search, sorting and filters are Ransack underneath, but the resource only names the attributes. The gem works out which control each one needs - a date range for a timestamp, a checkbox list for an enum - and keeps the query in the URL so a filtered list can be shared.",
  "Nesting follows Rails' own conventions. A resource mounted under another picks up its parent from the path, scopes its records to it, and builds the breadcrumb trail back up without being told how.",
  "When the defaults stop fitting, any view can be ejected and edited in place. Only the views you eject change; everything else keeps tracking the gem, so upgrades stay small.",
  "Ownership and authorisation sit on the resource too. A scope decides which records a request can see, and an optional Pundit policy decides what it can do with each one, down to the actions in a row's menu."
]

10.times do |i|
  owner = users[i % users.size]
  post = Post.find_or_initialize_by(title: "Post #{i + 1}")
  post.body = paragraphs.rotate(i).first(3).join("\n\n")
  post.user ||= owner
  post.save!
end

# Any post seeded before body was required - or left behind by a previous
# session - would now fail validation on its next save, which reads as a bug
# when you edit it rather than as the stale row it is.
Post.where(body: [nil, ""]).find_each do |post|
  post.update!(body: "This is the body of #{post.title.presence || "an untitled post"}.")
end

# Comments
Post.find_each do |post|
  3.times do |i|
    Comment.find_or_create_by!(post: post, body: "Comment #{i + 1} on #{post.title}")
  end
end

# Counters
User.find_each { |u| User.reset_counters(u.id, :posts) }
Post.find_each { |p| Post.reset_counters(p.id, :comments) }
