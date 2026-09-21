require "test_helper"

class LayeredResourceLayoutTest < ActionDispatch::IntegrationTest
  setup do
    # The registry is populated as the routes file is drawn, and the
    # assertions below read it without necessarily making a request first.
    Rails.application.reload_routes_unless_loaded

    @user = User.create!(
      email: "author@test.com",
      name: "Author",
      password: "password1234",
      password_confirmation: "password1234"
    )
    @user.posts.create!(title: "A post", body: "Body")
  end

  test "a route without layout: keeps the host's application layout" do
    get "/posts"

    assert_response :success
    assert_select "body.l-ui-body--always-show-navigation"
    assert_select "#boxed-layout", false
  end

  test "layout: renders the resource inside the named host layout" do
    get "/boxed/posts"

    assert_response :success
    assert_select "#boxed-layout table"
    assert_select "body.l-ui-body--always-show-navigation", false
  end

  test "layout: false renders without any layout" do
    get "/unwrapped/posts"

    assert_response :success
    assert_select "#boxed-layout", false
    assert_no_match(/<body/, response.body)
    assert_select "table"
  end

  test "the layout applies to the whole route, not just the index" do
    entry = Layered::Resource::Routing.lookup("boxed_posts")

    assert_equal "boxed", entry[:layout]
  end

  test "a route declaring no layout registers none" do
    entry = Layered::Resource::Routing.lookup("posts")

    assert_nil entry[:layout]
  end

  test "a non-name layout: is rejected at route-declaration time" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        layered_resources :posts, layout: 42
      end
    end

    assert_match(/layout: 42/, error.message)
  ensure
    Rails.application.reload_routes!
  end
end
