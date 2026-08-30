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
10.times do |i|
  owner = users[i % users.size]
  post = Post.find_or_initialize_by(title: "Post #{i + 1}")
  post.body = "This is the body of post #{i + 1}."
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
