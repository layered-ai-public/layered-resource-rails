require "test_helper"

class LayeredResourceInheritanceTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Author",
      password: "password1234",
      password_confirmation: "password1234"
    )
  end

  test "subclass inherits parent columns when not overridden" do
    # Sanity: AdminPostResource overrides columns
    refute_equal PostResource.columns, AdminPostResource.columns
  end

  test "subclass inherits parent search_fields when not overridden" do
    # AdminPostResource does not declare search_fields; it should inherit PostResource's
    assert_equal PostResource.search_fields, AdminPostResource.search_fields
    assert_equal [:title, :body], AdminPostResource.search_fields
  end

  test "subclass inherits parent model when not overridden" do
    assert_equal Post, AdminPostResource.model
  end

  test "subclass overrides take effect on its own route" do
    Post.create!(title: "Hello", body: "World", user: @user)
    get "/admin_posts"
    assert_response :success
    # AdminPostResource overrides columns to add :id; the parent route doesn't
    assert_select "th", text: "ID"

    get "/posts"
    assert_response :success
    assert_select "th", text: "ID", count: 0
  end

  test "subclass override of fields shows different form than parent" do
    record = Post.create!(title: "Existing", body: "Body", user: @user)

    get "/posts/#{record.id}/edit"
    assert_response :success
    assert_select "input[name='post[created_at]']"

    get "/admin_posts/#{record.id}/edit"
    assert_response :success
    # AdminPostResource fields omit :created_at
    assert_select "input[name='post[created_at]']", count: 0
    assert_select "input[name='post[title]']"
  end
end
