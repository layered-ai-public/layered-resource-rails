require "test_helper"

class ManagedResourceRoutingTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Author",
      password: "password",
      password_confirmation: "password"
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
        managed_resources :posts, only: [:destroy]
      end
    end
    assert_match(/without :index/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "only: [:new] without :index raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        managed_resources :posts, only: [:new]
      end
    end
    assert_match(/without :index/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "only: [:create] without :index raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        managed_resources :posts, only: [:create]
      end
    end
    assert_match(/without :index/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "only: [:index, :new] without :create raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        managed_resources :posts, only: %i[index new]
      end
    end
    assert_match(/without :create/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "only: [:index, :edit] without :update raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        managed_resources :posts, only: %i[index edit]
      end
    end
    assert_match(/without :update/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  # -- route key injection --

  test "query string cannot override _managed_route_key" do
    get "/users/#{@user.id}/readonly/posts", params: { _managed_route_key: "users_posts" }
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
          managed_resources :posts, resource: "PostResource", only: [:index]
        end
      end
    end
    entry = Layered::ManagedResource::Routing.instance_variable_get(:@registry)["admin_posts"]
    assert_equal "PostResource", entry[:resource]
  ensure
    Rails.application.reload_routes!
  end
end
