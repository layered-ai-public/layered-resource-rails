require "test_helper"

class LayeredResourceCrudTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Author",
      password: "password1234",
      password_confirmation: "password1234"
    )
  end

  # -- index --

  test "index renders with new link when crud enabled" do
    get "/users/#{@user.id}/posts"
    assert_response :success
    assert_select "a[href='/users/#{@user.id}/posts/new']", text: "New"
  end

  test "index renders edit and delete actions when crud enabled" do
    post = Post.create!(title: "Hello", user: @user)
    get "/users/#{@user.id}/posts"
    assert_response :success
    assert_select "a[href='/users/#{@user.id}/posts/#{post.id}/edit']", text: "Edit"
    assert_select "form[action='/users/#{@user.id}/posts/#{post.id}'] button", text: "Delete"
  end

  # -- show --

  test "show renders the primary column as the heading" do
    record = Post.create!(title: "Showcase", body: "Body text", user: @user)
    get "/posts/#{record.id}"
    assert_response :success
    assert_select "h1", text: "Showcase"
  end

  test "show renders edit and delete buttons when crud enabled" do
    record = Post.create!(title: "Showcase", user: @user)
    get "/posts/#{record.id}"
    assert_response :success
    assert_select "a[href='/posts/#{record.id}/edit']", text: "Edit"
    assert_select "form[action='/posts/#{record.id}'] button", text: "Delete"
  end

  test "show for missing record returns 404" do
    get "/posts/999999"
    assert_response :not_found
  end

  test "show renders without an index route registered" do
    record = Post.create!(title: "Standalone", user: @user)
    get "/showonly/posts/#{record.id}"
    assert_response :success
    assert_select "h1", text: "Standalone"
  end

  test "index links primary column to show when show is enabled" do
    record = Post.create!(title: "Linked", user: @user)
    get "/posts"
    assert_response :success
    assert_select "th[scope='row'] a[href='/posts/#{record.id}']", text: "Linked"
  end

  test "index does not link primary column when show is not enabled" do
    get "/users"
    assert_response :success
    # users route does not include :show, so the name cell should not link
    assert_select "th[scope='row'] a", text: "Author", count: 0
  end

  # -- new --

  test "new renders form" do
    get "/users/#{@user.id}/posts/new"
    assert_response :success
    assert_select "h1", /New post/i
    assert_select "form.l-ui-form"
    assert_select "input[name='post[title]']"
    assert_select "textarea[name='post[body]']"
  end

  # -- create --

  test "create with valid params redirects to index" do
    assert_difference "Post.count", 1 do
      post "/users/#{@user.id}/posts", params: { post: { title: "New post", body: "Content" } }
    end
    assert_redirected_to "/users/#{@user.id}/posts"
    follow_redirect!
    assert_select ".l-ui-notice--success", /created/i
  end

  test "create with invalid params re-renders with 422" do
    assert_no_difference "Post.count" do
      post "/users/#{@user.id}/posts", params: { post: { title: "" } }
    end
    assert_response :unprocessable_entity
    assert_select "form.l-ui-form"
    assert_select ".l-ui-form__errors"
  end

  test "create assigns post to parent user" do
    assert_difference "Post.count", 1 do
      post "/users/#{@user.id}/posts", params: { post: { title: "Nested post", body: "Content" } }
    end
    assert_equal @user, Post.last.user
  end

  # -- edit --

  test "edit renders form with existing values" do
    record = Post.create!(title: "Existing", body: "Body text", user: @user)
    get "/users/#{@user.id}/posts/#{record.id}/edit"
    assert_response :success
    assert_select "h1", /Edit post/i
    assert_select "input[name='post[title]'][value='Existing']"
    assert_select "textarea[name='post[body]']", text: "Body text"
  end

  # -- update --

  test "update with valid params redirects to index" do
    record = Post.create!(title: "Old title", user: @user)
    patch "/users/#{@user.id}/posts/#{record.id}", params: { post: { title: "New title" } }
    assert_redirected_to "/users/#{@user.id}/posts"
    assert_equal "New title", record.reload.title
  end

  test "update with invalid params re-renders with 422" do
    record = Post.create!(title: "Valid", user: @user)
    patch "/users/#{@user.id}/posts/#{record.id}", params: { post: { title: "" } }
    assert_response :unprocessable_entity
    assert_select "form.l-ui-form"
    assert_select ".l-ui-form__errors"
  end

  # -- destroy --

  test "destroy removes record and redirects to index" do
    record = Post.create!(title: "Doomed", user: @user)
    assert_difference "Post.count", -1 do
      delete "/users/#{@user.id}/posts/#{record.id}"
    end
    assert_redirected_to "/users/#{@user.id}/posts"
  end

  test "destroy for missing record returns 404" do
    delete "/users/#{@user.id}/posts/999999"
    assert_response :not_found
  end

  test "destroy handles halted callback gracefully" do
    record = Post.create!(title: "Protected", user: @user)
    Post.before_destroy { throw :abort }
    begin
      assert_no_difference "Post.count" do
        delete "/users/#{@user.id}/posts/#{record.id}"
      end
      assert_redirected_to "/users/#{@user.id}/posts"
      follow_redirect!
      assert_select ".l-ui-notice--warning", /could not be deleted/i
    ensure
      Post.reset_callbacks(:destroy)
    end
  end

  test "destroy works without fields" do
    record = Post.create!(title: "Hello", user: @user)
    original_fields = PostResource.instance_variable_get(:@fields)
    PostResource.instance_variable_set(:@fields, [])
    begin
      assert_difference "Post.count", -1 do
        delete "/users/#{@user.id}/deletable/posts/#{record.id}"
      end
      assert_redirected_to "/users/#{@user.id}/deletable/posts"
    ensure
      PostResource.instance_variable_set(:@fields, original_fields)
    end
  end

  # -- parent scoping --

  test "index only shows posts belonging to the parent user" do
    other_user = User.create!(email: "other@test.com", name: "Other", password: "password1234", password_confirmation: "password1234")
    Post.create!(title: "My post", user: @user)
    Post.create!(title: "Their post", user: other_user)

    get "/users/#{@user.id}/posts"
    assert_response :success
    assert_select "th[scope='row']", text: "My post"
    assert_select "th[scope='row']", text: "Their post", count: 0
  end

  test "edit for post belonging to different user returns 404" do
    other_user = User.create!(email: "other@test.com", name: "Other", password: "password1234", password_confirmation: "password1234")
    theirs = Post.create!(title: "Their post", user: other_user)

    get "/users/#{@user.id}/posts/#{theirs.id}/edit"
    assert_response :not_found
  end

  # -- standalone posts (no user scoping) --

  test "standalone index shows all posts regardless of user" do
    other_user = User.create!(email: "other@test.com", name: "Other", password: "password1234", password_confirmation: "password1234")
    Post.create!(title: "My post", user: @user)
    Post.create!(title: "Their post", user: other_user)

    get "/posts"
    assert_response :success
    assert_select "th[scope='row']", text: "My post"
    assert_select "th[scope='row']", text: "Their post"
  end

  test "standalone new renders form" do
    get "/posts/new"
    assert_response :success
    assert_select "form.l-ui-form"
  end

  test "standalone edit renders form" do
    record = Post.create!(title: "Standalone", body: "Body", user: @user)
    get "/posts/#{record.id}/edit"
    assert_response :success
    assert_select "input[name='post[title]'][value='Standalone']"
  end

  test "standalone destroy removes record" do
    record = Post.create!(title: "Gone", user: @user)
    assert_difference "Post.count", -1 do
      delete "/posts/#{record.id}"
    end
    assert_redirected_to "/posts"
  end
end
