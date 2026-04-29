require "test_helper"
require "rails/generators/test_case"
require "generators/layered/resource/column/column_generator"

class Layered::Resource::Generators::ColumnGeneratorTest < ::Rails::Generators::TestCase
  tests Layered::Resource::Generators::ColumnGenerator
  destination File.expand_path("../tmp/generators", __dir__)
  setup :prepare_destination

  test "ejects a built-in to the host-wide path" do
    run_generator ["badge"]

    assert_file "app/views/layered/resource/columns/_badge.html.erb" do |content|
      assert_match(/l-ui-badge/, content)
    end
  end

  test "ejects a built-in scoped to a resource" do
    run_generator ["badge", "questions"]

    assert_file "app/views/layered/questions/columns/_badge.html.erb" do |content|
      assert_match(/l-ui-badge/, content)
    end
  end

  test "scaffolds a starter partial for an unknown type" do
    run_generator ["priority_badge"]

    assert_file "app/views/layered/resource/columns/_priority_badge.html.erb" do |content|
      assert_match(/value/, content)
      assert_match(/Locals:/, content)
    end
  end

  test "scaffolds a custom type scoped to a resource" do
    run_generator ["priority_badge", "tickets"]

    assert_file "app/views/layered/tickets/columns/_priority_badge.html.erb"
  end

  test "prints next-step usage hint" do
    output = run_generator ["badge"]
    assert_match(/as: :badge/, output)
  end
end
