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

  # -- block form (member / collection) --

  test "block form generates routes for member actions" do
    Rails.application.routes.draw do
      layered_resources :posts, controller: "posts" do
        member do
          post :approve_payment
        end
      end
    end

    route = Rails.application.routes.routes.find { |r| r.path.spec.to_s == "/posts/:id/approve_payment(.:format)" }
    assert route, "expected /posts/:id/approve_payment route to be generated"
    assert_equal "posts", route.defaults[:controller]
    assert_equal "approve_payment", route.defaults[:action]
    assert_equal "posts", route.defaults[:_layered_resource_route_key]
  ensure
    Rails.application.reload_routes!
  end

  test "block form generates routes for collection actions" do
    Rails.application.routes.draw do
      layered_resources :posts, controller: "posts" do
        collection do
          post :bulk_archive
        end
      end
    end

    route = Rails.application.routes.routes.find { |r| r.path.spec.to_s == "/posts/bulk_archive(.:format)" }
    assert route, "expected /posts/bulk_archive route to be generated"
    assert_equal "bulk_archive", route.defaults[:action]
    assert_equal "posts", route.defaults[:_layered_resource_route_key]
  ensure
    Rails.application.reload_routes!
  end

  test "GET collection custom route is declared before show so it isn't shadowed" do
    Rails.application.routes.draw do
      layered_resources :posts, controller: "posts" do
        collection do
          get :bulk_archive
        end
      end
    end

    routes = Rails.application.routes.routes.to_a
    bulk_index = routes.index { |r| r.path.spec.to_s == "/posts/bulk_archive(.:format)" }
    show_index = routes.index { |r| r.path.spec.to_s == "/posts/:id(.:format)" && r.defaults[:action] == "show" }
    assert bulk_index, "expected bulk_archive route to be generated"
    assert show_index, "expected show route to be generated"
    assert bulk_index < show_index,
      "GET /posts/bulk_archive must be declared before GET /posts/:id or it will dispatch to show"
  ensure
    Rails.application.reload_routes!
  end

  test "block form raises when controller: is not overridden" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        layered_resources :posts do
          member do
            post :approve_payment
          end
        end
      end
    end
    assert_match(/no controller: override/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "block form raises when verb is declared outside member/collection" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        layered_resources :posts, controller: "posts" do
          post :stray_action
        end
      end
    end
    assert_match(/declared outside member\/collection/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "Routing.register records member and collection action names" do
    Rails.application.routes.draw do
      layered_resources :posts, controller: "posts" do
        member { post :approve_payment }
        collection { post :bulk_archive }
      end
    end

    entry = Layered::Resource::Routing.lookup("posts")
    assert_equal [:approve_payment], entry[:member_actions]
    assert_equal [:bulk_archive], entry[:collection_actions]
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
