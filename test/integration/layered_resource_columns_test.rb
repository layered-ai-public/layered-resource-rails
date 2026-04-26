require "test_helper"

class LayeredResourceColumnsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Author",
      password: "password1234",
      password_confirmation: "password1234"
    )
  end

  test "link option renders column value as badge link to nested layered resource" do
    Post.create!(title: "First", user: @user)
    Post.create!(title: "Second", user: @user)

    get "/users"
    assert_response :success
    assert_select "a[href='/users/#{@user.id}/posts'] span.l-ui-badge", text: "2"
  end

  test "column without link option renders plain value" do
    original_columns = UserResource.instance_variable_get(:@columns)
    UserResource.columns [
      { attribute: :name, primary: true },
      { attribute: :posts_count, label: "Posts" }
    ]
    begin
      get "/users"
      assert_response :success
      assert_select "td.l-ui-table__cell a", count: 0
    ensure
      UserResource.instance_variable_set(:@columns, original_columns)
    end
  end

  test "link option pointing at an unregistered route key raises" do
    original_columns = UserResource.instance_variable_get(:@columns)
    UserResource.columns [
      { attribute: :name, primary: true },
      { attribute: :posts_count, label: "Posts", link: :nope_does_not_exist }
    ]
    begin
      error = assert_raises(ArgumentError) { get "/users" }
      assert_match(/no layered_resources route is registered/, error.message)
    ensure
      UserResource.instance_variable_set(:@columns, original_columns)
    end
  end

  # -- sortability defaults --

  test "DB-backed columns are sortable by default" do
    Post.create!(title: "Hello", user: @user)
    get "/posts"
    assert_response :success
    # title is a real column on posts → header should render a sort link
    assert_select "a[href*='q%5Bs%5D=title']"
  end

  test "association-derived columns default to non-sortable" do
    Post.create!(title: "Hello", user: @user)
    get "/posts"
    assert_response :success
    # user_name is virtual (delegated) → no sort link, no q[s]=user_name in headers
    assert_select "a[href*='q%5Bs%5D=user_name']", count: 0
  end

  test "manually requesting a sort by an association-derived column does not 500" do
    Post.create!(title: "Hello", user: @user)
    get "/posts", params: { q: { s: "user_name asc" } }
    assert_response :success
  end

  test "sortable: true opts a virtual column back into sort links" do
    original_columns = PostResource.instance_variable_get(:@columns)
    PostResource.columns [
      { attribute: :title, primary: true },
      { attribute: :user_name, label: "Owner", sortable: true }
    ]
    begin
      Post.create!(title: "Hello", user: @user)
      get "/posts"
      assert_response :success
      assert_select "a[href*='q%5Bs%5D=user_name']"
    ensure
      PostResource.instance_variable_set(:@columns, original_columns)
    end
  end
end
