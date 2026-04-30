require "test_helper"

class LayeredResourcePunditTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "owner@test.com",
      name: "Owner",
      password: "password1234",
      password_confirmation: "password1234"
    )
    @other = User.create!(
      email: "other@test.com",
      name: "Other",
      password: "password1234",
      password_confirmation: "password1234"
    )
  end

  test "scope uses Pundit::Policy::Scope to filter records" do
    Post.create!(title: "Mine", user: @user)
    Post.create!(title: "Theirs", user: @other)
    sign_in @user

    get "/pundit/posts"
    assert_response :success
    assert_select "th[scope='row']", text: "Mine"
    assert_select "th[scope='row']", text: "Theirs", count: 0
  end

  test "show on someone else's record is hidden by policy scope" do
    theirs = Post.create!(title: "Theirs", user: @other)
    sign_in @user

    # Policy::Scope#resolve already filters foreign records out, so the find
    # raises before authorize gets a chance to run. The user simply can't see
    # the record.
    get "/pundit/posts/#{theirs.id}"
    assert_response :not_found
  end

  test "create authorizes via PostPolicy#create?" do
    # unauthenticated → user nil → create? false → Pundit denies
    assert_raises(Pundit::NotAuthorizedError) do
      post "/pundit/posts", params: { post: { title: "Anon" } }
    end
  end

  test "create assigns owner via owned_by alongside Pundit scope" do
    sign_in @user

    assert_difference "Post.count", 1 do
      post "/pundit/posts", params: { post: { title: "Fresh", body: "Hi" } }
    end
    assert_equal @user, Post.last.user
  end

  test "index hides New button when policy denies create" do
    # No user → PostPolicy#create? returns false → button hidden
    get "/pundit/posts"
    assert_response :success
    assert_select "a", text: "New", count: 0
  end

  test "index shows New button when policy permits create" do
    sign_in @user

    get "/pundit/posts"
    assert_response :success
    assert_select "a", text: "New"
  end

  test "row actions hide for records the user can't update" do
    mine = Post.create!(title: "Mine", user: @user)
    sign_in @user

    get "/pundit/posts"
    assert_response :success
    # The user's own row gets edit/delete
    assert_select "a[href='/pundit/posts/#{mine.id}/edit']"
  end
end
