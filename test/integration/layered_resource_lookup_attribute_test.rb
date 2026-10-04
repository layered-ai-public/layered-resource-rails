require "test_helper"

# ArticleResource addresses posts by `lookup_attribute :uid`, and its title
# column opts out of the primary-column link with `link: false`.
class LayeredResourceLookupAttributeTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Alice",
      password: "password1234",
      password_confirmation: "password1234"
    )
    @post = Post.create!(title: "Keyed", body: "Body", user: @user)
  end

  class InheritedResource < ArticleResource; end

  # -- lookup_attribute --

  test "defaults to id" do
    assert_equal :id, PostResource.lookup_attribute
  end

  test "is inherited" do
    assert_equal :uid, InheritedResource.lookup_attribute
  end

  test "edit finds the record by its lookup attribute" do
    get "/articles/#{@post.uid}/edit"

    assert_response :success
    assert_select "form[action='/articles/#{@post.uid}']"
  end

  test "show finds the record by its lookup attribute" do
    get "/articles/#{@post.uid}"

    assert_response :success
    assert_select "a[href='/articles/#{@post.uid}/edit']"
  end

  test "a record is not found by its id" do
    get "/articles/#{@post.id}/edit"

    assert_response :not_found
  end

  test "update and destroy find the record by its lookup attribute" do
    patch "/articles/#{@post.uid}", params: { post: { title: "Renamed" } }
    assert_redirected_to "/articles"
    assert_equal "Renamed", @post.reload.title

    assert_difference("Post.count", -1) do
      delete "/articles/#{@post.uid}"
    end
  end

  test "the index's row actions address the record by its lookup attribute" do
    get "/articles"

    assert_select "a[href='/articles/#{@post.uid}/edit']", text: "Edit"
    assert_select "form[action='/articles/#{@post.uid}']"
  end

  test "a link: column puts the parent's lookup attribute in the nested route" do
    get "/articles"

    assert_select "a[href='/articles/#{@post.uid}/comments']"
  end

  test "a parent crumb finds the parent by its resource's lookup attribute" do
    get "/articles/#{@post.uid}/comments"

    assert_response :success
    assert_select "nav.l-ui-breadcrumbs a[href='/articles']", text: "Posts"
    assert_select "nav.l-ui-breadcrumbs a[href='/articles/#{@post.uid}']", text: "Keyed"
  end

  test "with the default lookup attribute, member links still use to_param" do
    get "/posts"

    assert_select "a[href='/posts/#{@post.id}/edit']", text: "Edit"
  end

  # -- link: false --

  test "link: false leaves the primary column to its own render proc" do
    get "/articles"

    assert_select "a[href='/articles/#{@post.uid}']", text: "Keyed"
    assert_select "a[href='/articles/#{@post.uid}/edit']", text: "Keyed", count: 0
    assert_select "a a", count: 0
  end
end
