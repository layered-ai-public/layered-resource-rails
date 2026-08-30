require "bundler/setup"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

require "bundler/gem_tasks"

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = false
end

# `db:prepare` seeds, and the dummy app's seeds deliberately create more users
# than Layered::Resource.filter_combobox_threshold so the switch to a combobox
# is visible in bin/dev. Seeded rows in the test database would then change the
# control a filter renders as, so the suite loads the schema into a purged test
# database instead of inheriting whatever a previous `db:prepare` left behind.
task test: "app:db:test:prepare"

task default: :test
