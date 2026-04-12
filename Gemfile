source "https://rubygems.org"

gemspec development_group: [:development, :test]

# Use a local path for layered-ui-rails during development
if Dir.exist?(File.expand_path("../layered-ui-rails", __dir__))
  gem "layered-ui-rails", path: "../layered-ui-rails"
end
