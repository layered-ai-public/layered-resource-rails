require "test_helper"

class LayeredResourceNamespaceTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "ns@test.com",
      name: "NS",
      password: "password1234",
      password_confirmation: "password1234"
    )
  end

  test "infers resource class from surrounding namespace" do
    Post.create!(title: "Namespaced", user: @user)

    get "/custom_namespace/posts"
    assert_response :success
    # CustomNamespace::PostResource was selected via inflection (no resource: passed)
    assert_select "th[scope='row']", text: "Namespaced"
  end

  test "routes to namespaced ResourcesController, inheriting host controller chain" do
    get "/custom_namespace/posts"
    assert_response :success
    # Marker set by CustomNamespace::ApplicationController.
    # Proves the auto-detected CustomNamespace::ResourcesController is actually
    # used, rather than the default Layered::Resource::ResourcesController.
    assert_equal "1", @response.headers["X-Custom-Namespace-App-Controller"]
  end
end
