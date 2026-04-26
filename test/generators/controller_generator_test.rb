require "test_helper"
require "rails/generators/test_case"
require "generators/layered/resource/controller/controller_generator"

class Layered::Resource::Generators::ControllerGeneratorTest < ::Rails::Generators::TestCase
  tests Layered::Resource::Generators::ControllerGenerator
  destination File.expand_path("../tmp/generators", __dir__)
  setup :prepare_destination

  test "generates a controller that inherits from the base" do
    run_generator ["articles"]

    assert_file "app/controllers/articles_controller.rb" do |content|
      assert_match(/class ArticlesController < Layered::Resource::ResourcesController/, content)
    end
  end

  test "strips a trailing _controller suffix from the name" do
    run_generator ["posts_controller"]

    assert_file "app/controllers/posts_controller.rb" do |content|
      assert_match(/class PostsController < Layered::Resource::ResourcesController/, content)
    end
  end

  test "respects namespaced names" do
    run_generator ["admin/articles"]

    assert_file "app/controllers/admin/articles_controller.rb" do |content|
      assert_match(/class Admin::ArticlesController < Layered::Resource::ResourcesController/, content)
    end
  end

  test "prints the routes hint" do
    output = run_generator ["articles"]
    assert_match(/layered_resources :articles, controller: "articles"/, output)
  end

  test "wraps the routes hint in a namespace block for namespaced names" do
    output = run_generator ["admin/articles"]
    assert_match(/namespace :admin do/, output)
    assert_match(/layered_resources :articles, controller: "articles"/, output)
  end
end
