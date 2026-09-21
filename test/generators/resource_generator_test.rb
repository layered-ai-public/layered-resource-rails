require "test_helper"
require "rails/generators/test_case"
require "generators/layered/resource/resource_generator"

class Layered::Resource::Generators::ResourceGeneratorTest < ::Rails::Generators::TestCase
  tests Layered::Resource::Generators::ResourceGenerator
  destination File.expand_path("../tmp/generators", __dir__)
  setup :prepare_destination

  def write_empty_routes
    Dir.mkdir(File.join(destination_root, "config")) unless File.directory?(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config", "routes.rb"), "Rails.application.routes.draw do\nend\n")
  end

  test "generates the resource file but not a model" do
    write_empty_routes
    run_generator ["article", "title:string", "body:text"]

    assert_file "app/layered_resources/article_resource.rb" do |content|
      assert_match(/class ArticleResource < Layered::Resource::Base/, content)
      assert_match(/model Article/, content)
      assert_match(/\{ attribute: :title, primary: true \}/, content)
      assert_match(/\{ attribute: :body, as: :text \}/, content)
    end

    assert_no_file "app/models/article.rb"
  end

  test "appends a layered_resources route" do
    write_empty_routes

    run_generator ["article"]

    assert_file "config/routes.rb" do |content|
      assert_match(/layered_resources :articles/, content)
    end
  end

  test "--skip-route leaves routes.rb untouched" do
    write_empty_routes
    routes = File.read(File.join(destination_root, "config", "routes.rb"))

    run_generator ["article", "--skip-route"]

    assert_file "config/routes.rb" do |content|
      assert_equal routes, content
    end
  end

  test "a reference is left out of columns but kept as a foreign-key field" do
    write_empty_routes
    run_generator ["talk", "title:string", "speaker:references"]

    assert_file "app/layered_resources/talk_resource.rb" do |content|
      assert_match(/\{ attribute: :title, primary: true \}/, content)
      assert_no_match(/\{ attribute: :speaker[,\s}]/, content)
      assert_match(/\{ attribute: :speaker_id \}/, content)
    end
  end

  test "a polymorphic reference is left out of fields too" do
    write_empty_routes
    run_generator ["talk", "title:string", "speaker:references{polymorphic}"]

    assert_file "app/layered_resources/talk_resource.rb" do |content|
      assert_no_match(/attribute: :speaker/, content)
    end
  end

  test "a reference-only resource still emits fields" do
    write_empty_routes
    run_generator ["talk", "speaker:references"]

    assert_file "app/layered_resources/talk_resource.rb" do |content|
      assert_no_match(/columns \[/, content)
      assert_match(/fields \[\n    \{ attribute: :speaker_id \}\n  \]/, content)
    end
  end

  test "singularises the resource name" do
    write_empty_routes
    run_generator ["articles"]

    assert_file "app/layered_resources/article_resource.rb" do |content|
      assert_match(/class ArticleResource < Layered::Resource::Base/, content)
    end
  end
end
