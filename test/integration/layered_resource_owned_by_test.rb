require "test_helper"

class LayeredResourceOwnedByTest < ActionDispatch::IntegrationTest
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

  test "scope returns model.none when no current_user (footgun defuse)" do
    Post.create!(title: "Mine", user: @user)
    Post.create!(title: "Theirs", user: @other)

    get "/owned/posts"
    assert_response :success
    assert_select "th[scope='row']", text: "Mine", count: 0
    assert_select "th[scope='row']", text: "Theirs", count: 0
  end

  test "scope filters records to the signed-in user" do
    Post.create!(title: "Mine", user: @user)
    Post.create!(title: "Theirs", user: @other)
    sign_in @user

    get "/owned/posts"
    assert_response :success
    assert_select "th[scope='row']", text: "Mine"
    assert_select "th[scope='row']", text: "Theirs", count: 0
  end

  test "edit on someone else's record returns 404" do
    theirs = Post.create!(title: "Theirs", user: @other)
    sign_in @user

    get "/owned/posts/#{theirs.id}/edit"
    assert_response :not_found
  end

  test "create assigns the signed-in user as owner" do
    sign_in @user

    assert_difference "Post.count", 1 do
      post "/owned/posts", params: { post: { title: "Fresh", body: "Hi" } }
    end
    assert_equal @user, Post.last.user
  end
end
