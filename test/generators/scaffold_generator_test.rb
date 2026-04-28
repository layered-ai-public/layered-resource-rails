require "test_helper"
require "rails/generators/test_case"
require "generators/layered/resource/scaffold/scaffold_generator"

class Layered::Resource::Generators::ScaffoldGeneratorTest < ::Rails::Generators::TestCase
  tests Layered::Resource::Generators::ScaffoldGenerator
  destination File.expand_path("../tmp/generators", __dir__)
  setup :prepare_destination

  test "generates the resource file with columns and fields from attributes" do
    run_generator ["article", "title:string", "body:text", "--skip-model"]

    assert_file "app/layered_resources/article_resource.rb" do |content|
      assert_match(/class ArticleResource < Layered::Resource::Base/, content)
      assert_match(/model Article/, content)
      assert_match(/\{ attribute: :title, primary: true \}/, content)
      assert_match(/\{ attribute: :body \}/, content)
      assert_match(/\{ attribute: :body, as: :text \}/, content)
    end
  end

  test "singularises the resource name" do
    run_generator ["articles", "--skip-model"]

    assert_file "app/layered_resources/article_resource.rb" do |content|
      assert_match(/class ArticleResource < Layered::Resource::Base/, content)
      assert_match(/model Article/, content)
    end
  end

  test "skips columns and fields blocks when no attributes are given" do
    run_generator ["article", "--skip-model"]

    assert_file "app/layered_resources/article_resource.rb" do |content|
      assert_no_match(/columns \[/, content)
      assert_no_match(/fields \[/, content)
    end
  end

  test "appends a layered_resources route" do
    Dir.mkdir(File.join(destination_root, "config")) unless File.directory?(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config", "routes.rb"), <<~RUBY)
      Rails.application.routes.draw do
      end
    RUBY

    run_generator ["article", "--skip-model"]

    assert_file "config/routes.rb" do |content|
      assert_match(/layered_resources :articles/, content)
    end
  end

  test "passes --actions through to the route as only:" do
    Dir.mkdir(File.join(destination_root, "config")) unless File.directory?(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config", "routes.rb"), "Rails.application.routes.draw do\nend\n")

    run_generator ["article", "--skip-model", "--actions", "index", "show"]

    assert_file "config/routes.rb" do |content|
      assert_match(/layered_resources :articles, only: \[:index, :show\]/, content)
    end
  end

  test "passes --except through to the route as except:" do
    Dir.mkdir(File.join(destination_root, "config")) unless File.directory?(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config", "routes.rb"), "Rails.application.routes.draw do\nend\n")

    run_generator ["article", "--skip-model", "--except", "destroy"]

    assert_file "config/routes.rb" do |content|
      assert_match(/layered_resources :articles, except: \[:destroy\]/, content)
    end
  end

  test "--controller ejects a controller and wires the route to it" do
    Dir.mkdir(File.join(destination_root, "config")) unless File.directory?(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config", "routes.rb"), "Rails.application.routes.draw do\nend\n")

    run_generator ["article", "--skip-model", "--controller"]

    assert_file "app/controllers/articles_controller.rb" do |content|
      assert_match(/class ArticlesController < Layered::Resource::ResourcesController/, content)
    end
    assert_file "config/routes.rb" do |content|
      assert_match(/layered_resources :articles, controller: "articles"/, content)
    end
  end

  test "--views ejects all four view templates" do
    run_generator ["article", "--skip-model", "--views"]

    %w[index show new edit].each do |view|
      assert_file "app/views/layered/articles/#{view}.html.erb"
    end
  end

  test "prints next-step advice covering validations, default_sort, and search_fields" do
    Dir.mkdir(File.join(destination_root, "config")) unless File.directory?(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config", "routes.rb"), "Rails.application.routes.draw do\nend\n")

    output = run_generator ["article", "--skip-model"]

    assert_match(/validates/, output)
    assert_match(/default_sort/, output)
    assert_match(/search_fields/, output)
  end

  test "skips reference attributes from columns and fields" do
    run_generator ["post", "title:string", "user:references", "--skip-model"]

    assert_file "app/layered_resources/post_resource.rb" do |content|
      assert_match(/\{ attribute: :title, primary: true \}/, content)
      assert_no_match(/attribute: :user\b/, content)
    end
  end
end
