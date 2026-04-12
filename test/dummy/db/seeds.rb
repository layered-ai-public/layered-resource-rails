user = User.find_or_create_by!(email: "admin@example.com") do |u|
  u.name = "Admin"
  u.password = "password"
  u.password_confirmation = "password"
end

10.times do |i|
  Post.find_or_create_by!(title: "Post #{i + 1}") do |p|
    p.body = "This is the body of post #{i + 1}."
    p.user = user
  end
end

puts "Seeded #{User.count} user(s) and #{Post.count} post(s)."
