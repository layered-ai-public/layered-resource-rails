require "test_helper"

# aria-current="page" belongs on the crumb that is the current page, and
# nowhere else. The trail's parent crumbs - linked or not - never carry it.
class LayeredResourceBreadcrumbCurrentTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Author",
      password: "password1234",
      password_confirmation: "password1234"
    )
    @post = Post.create!(title: "Hello", user: @user, body: "Body")
  end

  test "nested index marks the collection, not the parent record, as current" do
    get "/users/#{@user.id}/posts"
    assert_response :success

    assert_select "nav.l-ui-breadcrumbs li" do |items|
      assert_equal ["Users", "Author", "Posts"], items.map { |li| li.text.strip }
    end
    assert_current_crumb "Posts"
  end

  test "an unlinked parent record crumb carries no aria-current" do
    get "/users/#{@user.id}/posts"
    assert_response :success

    # Users routes no :show action, so "Author" is plain text - but it is
    # not the current page.
    assert_select "nav.l-ui-breadcrumbs li", text: "Author" do |items|
      assert_nil items.first.at_css("[aria-current]")
    end
  end

  test "a parent record links to its show page when the parent routes one" do
    comment = @post.comments.create!(body: "Nice")

    get "/users/#{@user.id}/posts/#{@post.id}/comments"
    assert_response :success
    assert comment.persisted?

    assert_select "nav.l-ui-breadcrumbs a[href=?]", "/users/#{@user.id}/posts/#{@post.id}", text: "Hello"
    assert_current_crumb "Comments"
  end

  test "show marks the record as current and links the index above it" do
    get "/detailonly/posts/#{@post.id}"
    assert_response :success

    assert_select "nav.l-ui-breadcrumbs a[href='/detailonly/posts']", text: "Posts"
    assert_current_crumb "Hello"
  end

  test "new marks itself as current" do
    get "/posts/new"
    assert_response :success

    assert_select "nav.l-ui-breadcrumbs a[href='/posts']", text: "Posts"
    assert_current_crumb "New"
  end

  test "edit marks itself as current" do
    get "/users/#{@user.id}/edit"
    assert_response :success

    assert_current_crumb "Edit"
  end

  test "a trail carries exactly one current crumb" do
    get "/users/#{@user.id}/posts/#{@post.id}/edit"
    assert_response :success

    assert_select "nav.l-ui-breadcrumbs [aria-current='page']", count: 1
  end

  private

  def assert_current_crumb(label)
    assert_select "nav.l-ui-breadcrumbs [aria-current='page']", count: 1, text: label
  end
end
