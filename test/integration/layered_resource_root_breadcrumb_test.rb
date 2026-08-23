require "test_helper"

class LayeredResourceRootBreadcrumbTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Author",
      password: "password1234",
      password_confirmation: "password1234"
    )
  end

  test "index renders no breadcrumb trail without a root_breadcrumb" do
    get "/posts"
    assert_response :success
    assert_select "nav.l-ui-breadcrumbs", count: 0
  end

  test "index renders a linked root_breadcrumb" do
    get "/users"
    assert_response :success
    assert_select "nav.l-ui-breadcrumbs a[href='/']", text: "Home"
  end

  test "root_breadcrumb comes before the derived trail on member pages" do
    get "/users/#{@user.id}/edit"
    assert_response :success
    assert_select "nav.l-ui-breadcrumbs li" do |items|
      assert_equal ["Home", "Users"], items.map { |li| li.text.strip }
      assert_equal "/", items.first.at_css("a")["href"]
    end
  end

  test "show renders no breadcrumb trail when there is nothing to show" do
    record = Post.create!(title: "Hello", user: @user, body: "Body")
    get "/showonly/posts/#{record.id}"
    assert_response :success
    assert_select "nav.l-ui-breadcrumbs", count: 0
  end

  test "root_breadcrumb is inherited by resource subclasses" do
    subclass = Class.new(UserResource)
    assert_equal({ label: "Home", path: "/" }, subclass.root_breadcrumb)
  end
end
