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

  test "raises when via returns nil and allow_nil is not set" do
    Post.create!(title: "Mine", user: @user, body: "Body")

    assert_raises(Layered::Resource::MissingOwnerError) do
      get "/owned/posts"
    end
  end

  test "with allow_nil: true returns model.none when via returns nil" do
    Post.create!(title: "Mine", user: @user, body: "Body")
    Post.create!(title: "Theirs", user: @other, body: "Body")

    get "/public_owned/posts"
    assert_response :success
    assert_select "th[scope='row']", text: "Mine", count: 0
    assert_select "th[scope='row']", text: "Theirs", count: 0
  end

  test "scope filters records to the signed-in user" do
    Post.create!(title: "Mine", user: @user, body: "Body")
    Post.create!(title: "Theirs", user: @other, body: "Body")
    sign_in @user

    get "/owned/posts"
    assert_response :success
    assert_select "th[scope='row']", text: "Mine"
    assert_select "th[scope='row']", text: "Theirs", count: 0
  end

  test "edit on someone else's record returns 404" do
    theirs = Post.create!(title: "Theirs", user: @other, body: "Body")
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
