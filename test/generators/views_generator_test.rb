require "test_helper"
require "rails/generators/test_case"
require "generators/layered/resource/views/views_generator"

class Layered::Resource::Generators::ViewsGeneratorTest < ::Rails::Generators::TestCase
  tests Layered::Resource::Generators::ViewsGenerator
  destination File.expand_path("../tmp/generators", __dir__)
  setup :prepare_destination

  test "copies all four view templates into app/views/layered/<name>/" do
    run_generator ["articles"]

    assert_file "app/views/layered/articles/index.html.erb"
    assert_file "app/views/layered/articles/show.html.erb"
    assert_file "app/views/layered/articles/new.html.erb"
    assert_file "app/views/layered/articles/edit.html.erb"
  end

  test "pluralises a singular resource name" do
    run_generator ["article"]

    assert_file "app/views/layered/articles/index.html.erb"
  end

  test "ignores Rails namespaces and uses the plural resource name only" do
    # The controller's escape hatch looks in layered/<resource_name>/,
    # which never includes a namespace prefix, so generated files must
    # land in the same flat location regardless of how the user names
    # the generator argument.
    run_generator ["admin/articles"]

    assert_file "app/views/layered/articles/index.html.erb"
    assert_no_file "app/views/layered/admin/articles/index.html.erb"
  end

  test "templates contain the gem's default content" do
    run_generator ["articles"]

    assert_file "app/views/layered/articles/index.html.erb" do |content|
      assert_match(/l_ui_table/, content)
    end
  end

  test "prints next-steps hint" do
    output = run_generator ["articles"]
    assert_match(%r{app/views/layered/articles/}, output)
  end
end
