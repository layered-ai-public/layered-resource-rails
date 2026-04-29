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

  # -- as: dispatch --

  test "as: :datetime renders the built-in datetime partial" do
    swap_columns(PostResource,
      [{ attribute: :title, primary: true },
       { attribute: :created_at, as: :datetime }]) do
      Post.create!(title: "Hello", user: @user, created_at: Time.utc(2026, 4, 15, 10, 30))
      get "/posts"
      assert_response :success
      assert_select "td.l-ui-table__cell", text: "15 Apr 2026 10:30"
    end
  end

  test "as: :datetime accepts a custom format via options" do
    swap_columns(PostResource,
      [{ attribute: :title, primary: true },
       { attribute: :created_at, as: :datetime, format: "%Y-%m-%d" }]) do
      Post.create!(title: "Hello", user: @user, created_at: Time.utc(2026, 4, 15))
      get "/posts"
      assert_response :success
      assert_select "td.l-ui-table__cell", text: "2026-04-15"
    end
  end

  test "as: :badge wraps the value in a layered-ui badge" do
    swap_columns(PostResource,
      [{ attribute: :title, primary: true, as: :badge,
         variants: { Hello: :success } }]) do
      Post.create!(title: "Hello", user: @user)
      get "/posts"
      assert_response :success
      assert_select "th.l-ui-table__cell--primary span.l-ui-badge.l-ui-badge--success", text: "Hello"
    end
  end

  test "as: :badge falls back to the default variant when the value isn't mapped" do
    swap_columns(PostResource,
      [{ attribute: :title, primary: true, as: :badge }]) do
      Post.create!(title: "Hello", user: @user)
      get "/posts"
      assert_response :success
      assert_select "span.l-ui-badge.l-ui-badge--default", text: "Hello"
    end
  end

  test "as: :badge renders integer values without raising" do
    swap_columns(UserResource,
      [{ attribute: :name, primary: true },
       { attribute: :posts_count, as: :badge, variants: { "0": :default } }]) do
      get "/users"
      assert_response :success
      assert_select "span.l-ui-badge", text: "0"
    end
  end

  test "as: :boolean partial renders the configured true/false labels" do
    truthy = ApplicationController.renderer.render(
      partial: "layered/resource/columns/boolean",
      locals: { record: nil, value: true, options: { true_label: "yes", false_label: "no" } }
    )
    falsy = ApplicationController.renderer.render(
      partial: "layered/resource/columns/boolean",
      locals: { record: nil, value: false, options: { true_label: "yes", false_label: "no" } }
    )
    assert_equal "yes", truthy.strip
    assert_equal "no", falsy.strip
  end

  test "as: :boolean partial defaults to ✓/✗ glyphs" do
    truthy = ApplicationController.renderer.render(
      partial: "layered/resource/columns/boolean",
      locals: { record: nil, value: true, options: {} }
    )
    falsy = ApplicationController.renderer.render(
      partial: "layered/resource/columns/boolean",
      locals: { record: nil, value: false, options: {} }
    )
    assert_equal "✓", truthy.strip
    assert_equal "✗", falsy.strip
  end

  test "as: with an unknown type raises ArgumentError" do
    swap_columns(PostResource,
      [{ attribute: :title, primary: true, as: :nope_doesnt_exist }]) do
      Post.create!(title: "Hello", user: @user)
      error = assert_raises(ArgumentError) { get "/posts" }
      assert_match(/No column partial found for as: :nope_doesnt_exist/, error.message)
    end
  end

  test "per-resource column partial overrides the gem default" do
    # Override partial lives at test/dummy/app/views/layered/posts/columns/_text.html.erb.
    swap_columns(PostResource,
      [{ attribute: :title, primary: true, as: :text }]) do
      Post.create!(title: "Hello", user: @user)
      get "/posts"
      assert_response :success
      assert_select "th.l-ui-table__cell--primary span.per-resource-text-override", text: "Hello"
    end
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

  private

  def swap_columns(resource_class, new_columns)
    original = resource_class.instance_variable_get(:@columns)
    resource_class.columns new_columns
    yield
  ensure
    resource_class.instance_variable_set(:@columns, original)
  end
end
