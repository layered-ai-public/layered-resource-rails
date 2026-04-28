require "test_helper"

class LayeredResourceRoutingTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Author",
      password: "password1234",
      password_confirmation: "password1234"
    )
  end

  # -- only: option --

  test "only: [:index] hides new link" do
    get "/users/#{@user.id}/readonly/posts"
    assert_response :success
    assert_select "a[href$='/posts/new']", count: 0
  end

  test "only: [:index] excludes CRUD routes" do
    record = Post.create!(title: "Hello", user: @user)
    get "/users/#{@user.id}/readonly/posts/new"
    assert_response :not_found

    get "/users/#{@user.id}/readonly/posts/#{record.id}/edit"
    assert_response :not_found

    delete "/users/#{@user.id}/readonly/posts/#{record.id}"
    assert_response :not_found
  end

  test "only: [:destroy] without :index raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        layered_resources :posts, only: [:destroy]
      end
    end
    assert_match(/without :index/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "only: [:new] without :index raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        layered_resources :posts, only: [:new]
      end
    end
    assert_match(/without :index/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "only: [:create] without :index raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        layered_resources :posts, only: [:create]
      end
    end
    assert_match(/without :index/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "only: [:index, :new] without :create raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        layered_resources :posts, only: %i[index new]
      end
    end
    assert_match(/without :create/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "only: [:index, :edit] without :update raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        layered_resources :posts, only: %i[index edit]
      end
    end
    assert_match(/without :update/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  # -- except: option --

  test "except: removes actions from the registered resource" do
    Rails.application.routes.draw do
      layered_resources :posts, except: %i[new create edit update destroy]
    end

    entry = Layered::Resource::Routing.lookup("posts")
    assert_equal %i[index show], entry[:actions]
  ensure
    Rails.application.reload_routes!
  end

  test "except: excludes generated routes" do
    Rails.application.routes.draw do
      layered_resources :posts, except: %i[new create edit update destroy]
    end

    paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }
    assert_includes paths, "/posts(.:format)"
    assert_includes paths, "/posts/:id(.:format)"
    assert_not_includes paths, "/posts/new(.:format)"
    assert_not_includes paths, "/posts/:id/edit(.:format)"
  ensure
    Rails.application.reload_routes!
  end

  # -- route key injection --

  test "query string cannot override _layered_resource_route_key" do
    get "/users/#{@user.id}/readonly/posts", params: { _layered_resource_route_key: "users_posts" }
    assert_response :success
    assert_select "a[href$='/posts/new']", count: 0,
      message: "Full-CRUD actions must not leak via query string override"
  end

  # -- namespace / scope --

  test "scope with path prefix infers base model not namespaced model" do
    Post.create!(title: "Scoped", user: @user)
    get "/users/#{@user.id}/admin/posts"
    assert_response :success
    assert_select "th", text: "Title"
  end

  test "namespace does not infer namespaced model for main app routes" do
    assert_nothing_raised do
      Rails.application.routes.draw do
        namespace :admin do
          layered_resources :posts, resource: "PostResource", only: [:index]
        end
      end
    end
    entry = Layered::Resource::Routing.instance_variable_get(:@registry)["admin_posts"]
    assert_equal "PostResource", entry[:resource]
  ensure
    Rails.application.reload_routes!
  end

  # -- controller: option --

  test "controller: option routes to a custom controller" do
    Rails.application.routes.draw do
      layered_resources :posts, controller: "custom_posts", only: [:index]
    end
    route = Rails.application.routes.routes.find { |r| r.path.spec.to_s == "/posts(.:format)" }
    assert_equal "custom_posts", route.defaults[:controller]
  ensure
    Rails.application.reload_routes!
  end
end
