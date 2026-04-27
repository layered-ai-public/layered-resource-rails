require "test_helper"
require "tmpdir"
require "fileutils"

class LayeredResourceViewOverrideTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Author",
      password: "password1234",
      password_confirmation: "password1234"
    )

    @tmpdir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@tmpdir, "layered/posts"))
    File.write(
      File.join(@tmpdir, "layered/posts/index.html.erb"),
      %(<h1 id="custom-posts-index">Custom posts index</h1>)
    )

    @controller_class = Layered::Resource::ResourcesController
    @controller_class.prepend_view_path(@tmpdir)
  end

  teardown do
    remaining = @controller_class.view_paths.reject { |p| p.to_s.start_with?(@tmpdir) }
    @controller_class.view_paths = remaining
    FileUtils.remove_entry(@tmpdir)
  end

  test "custom view in app/views/layered/<resource_name>/ overrides gem default" do
    get "/posts"
    assert_response :success
    assert_select "h1#custom-posts-index", text: "Custom posts index"
  end

  test "scoped routes with the same resource name pick up the override" do
    get "/users/#{@user.id}/posts"
    assert_response :success
    assert_select "h1#custom-posts-index", text: "Custom posts index"
  end

  test "resources without an override fall back to the gem default" do
    get "/users"
    assert_response :success
    assert_select "h1.l-ui-heading", text: /Users/
    assert_select "h1#custom-posts-index", count: 0
  end
end
