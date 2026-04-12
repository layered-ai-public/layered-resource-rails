require "test_helper"

class ManagedResourceCrudTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Author",
      password: "password",
      password_confirmation: "password"
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

  # -- parent scoping --

  test "index only shows posts belonging to the parent user" do
    other_user = User.create!(email: "other@test.com", name: "Other", password: "password", password_confirmation: "password")
    mine = Post.create!(title: "My post", user: @user)
    theirs = Post.create!(title: "Their post", user: other_user)

    get "/users/#{@user.id}/posts"
    assert_response :success
    assert_select "th[scope='row']", text: "My post"
    assert_select "th[scope='row']", text: "Their post", count: 0
  end

  test "edit for post belonging to different user returns 404" do
    other_user = User.create!(email: "other@test.com", name: "Other", password: "password", password_confirmation: "password")
    theirs = Post.create!(title: "Their post", user: other_user)

    get "/users/#{@user.id}/posts/#{theirs.id}/edit"
    assert_response :not_found
  end

  # -- standalone posts (no user scoping) --

  test "standalone index shows all posts regardless of user" do
    other_user = User.create!(email: "other@test.com", name: "Other", password: "password", password_confirmation: "password")
    mine = Post.create!(title: "My post", user: @user)
    theirs = Post.create!(title: "Their post", user: other_user)

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

  # -- route key injection --

  test "query string cannot override _managed_route_key" do
    get "/users/#{@user.id}/readonly/posts", params: { _managed_route_key: "users_posts" }
    assert_response :success
    assert_select "a[href$='/posts/new']", count: 0,
      message: "Full-CRUD actions must not leak via query string override"
  end

  # -- only: option --

  test "only: [:index] hides new link" do
    get "/users/#{@user.id}/readonly/posts"
    assert_response :success
    assert_select "a[href$='/posts/new']", count: 0
  end

  test "only: [:index] excludes CRUD routes" do
    record = Post.create!(title: "Hello", user: @user)
    get "/users/#{@user.id}/readonly/posts/new"
    assert_response :not_found

    get "/users/#{@user.id}/readonly/posts/#{record.id}/edit"
    assert_response :not_found

    delete "/users/#{@user.id}/readonly/posts/#{record.id}"
    assert_response :not_found
  end

  test "only: [:destroy] without :index raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        managed_resources :posts, only: [:destroy]
      end
    end
    assert_match(/without :index/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "only: [:new] without :index raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        managed_resources :posts, only: [:new]
      end
    end
    assert_match(/without :index/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "only: [:create] without :index raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        managed_resources :posts, only: [:create]
      end
    end
    assert_match(/without :index/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "only: [:index, :new] without :create raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        managed_resources :posts, only: %i[index new]
      end
    end
    assert_match(/without :create/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "only: [:index, :edit] without :update raises at route definition" do
    error = assert_raises(ArgumentError) do
      Rails.application.routes.draw do
        managed_resources :posts, only: %i[index edit]
      end
    end
    assert_match(/without :update/, error.message)
  ensure
    Rails.application.reload_routes!
  end

  test "scope with path prefix infers base model not namespaced model" do
    Post.create!(title: "Scoped", user: @user)
    get "/users/#{@user.id}/admin/posts"
    assert_response :success
    assert_select "th", text: "Title"
  end

  test "namespace does not infer namespaced model for main app routes" do
    assert_nothing_raised do
      Rails.application.routes.draw do
        namespace :admin do
          managed_resources :posts, resource: "PostResource", only: [:index]
        end
      end
    end
    entry = Layered::ManagedResource::Routing.instance_variable_get(:@registry)["admin_posts"]
    assert_equal "PostResource", entry[:resource]
  ensure
    Rails.application.reload_routes!
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
end
