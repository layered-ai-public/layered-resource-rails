users = [
  { name: "Alice", email: "alice@example.com" },
  { name: "Bob", email: "bob@example.com" },
  { name: "Charlie", email: "charlie@example.com" }
].map do |attrs|
  User.find_or_create_by!(email: attrs[:email]) do |u|
    u.name = attrs[:name]
    u.password = "password"
    u.password_confirmation = "password"
  end
end

10.times do |i|
  owner = users[i % users.size]
  Post.find_or_create_by!(title: "Post #{i + 1}") do |p|
    p.body = "This is the body of post #{i + 1}."
    p.user = owner
  end
end

puts "Seeded #{User.count} user(s) and #{Post.count} post(s)."
