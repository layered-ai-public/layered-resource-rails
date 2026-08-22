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

  test "index renders edit and delete actions in a popover menu when crud enabled" do
    post = Post.create!(title: "Hello", user: @user, body: "Body")
    get "/users/#{@user.id}/posts"
    assert_response :success
    assert_select "td.l-ui-table__cell--action [data-controller~='l-ui--popover']" do
      assert_select "button[popovertarget][aria-label='Actions for Hello']"
      assert_select ".l-ui-popover__menu a[href='/users/#{@user.id}/posts/#{post.id}/edit']", text: "Edit"
      assert_select ".l-ui-popover__menu form[action='/users/#{@user.id}/posts/#{post.id}'] button", text: "Delete"
    end
  end

  test "index pins the actions column while the table scrolls horizontally" do
    Post.create!(title: "Hello", user: @user, body: "Body")
    get "/users/#{@user.id}/posts"
    assert_response :success
    assert_select "table.l-ui-table.l-ui-table--floating-actions"
  end

  # -- show --

  test "show renders the primary column as the heading" do
    record = Post.create!(title: "Showcase", body: "Body text", user: @user)
    get "/posts/#{record.id}"
    assert_response :success
    assert_select "h1", text: "Showcase"
  end

  test "show renders edit and delete buttons when crud enabled" do
    record = Post.create!(title: "Showcase", user: @user, body: "Body")
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
    record = Post.create!(title: "Standalone", user: @user, body: "Body")
    get "/showonly/posts/#{record.id}"
    assert_response :success
    assert_select "h1", text: "Standalone"
  end

  test "index links primary column to edit when editable" do
    record = Post.create!(title: "Linked", user: @user, body: "Body")
    get "/posts"
    assert_response :success
    assert_select "th[scope='row'] a[href='/posts/#{record.id}/edit']", text: "Linked"
  end

  test "index links primary column to show when not editable but show is enabled" do
    record = Post.create!(title: "Detail", user: @user, body: "Body")
    get "/detailonly/posts"
    assert_response :success
    # /detailonly/posts is only: [:index, :show] - no edit, so the title falls
    # back to the show page.
    assert_select "th[scope='row'] a[href='/detailonly/posts/#{record.id}']", text: "Detail"
  end

  test "index does not link primary column when neither edit nor show is enabled" do
    get "/readonly/users"
    assert_response :success
    # /readonly/users is only: [:index] - nothing to link the title to.
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

  test "create flash respects host i18n override" do
    I18n.backend.store_translations(:xx, layered: { resource: { flash: { created: "%{model} added successfully" } } })
    I18n.backend.store_translations(:xx, activerecord: { models: { post: "Post" } })
    original_locale = I18n.locale
    original_available = I18n.available_locales
    I18n.available_locales = original_available + [:xx]
    I18n.locale = :xx
    begin
      post "/users/#{@user.id}/posts", params: { post: { title: "Hi", body: "Body" } }
      follow_redirect!
      assert_select ".l-ui-notice--success", text: /Post added successfully/
    ensure
      I18n.locale = original_locale
      I18n.available_locales = original_available
    end
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
    record = Post.create!(title: "Old title", user: @user, body: "Body")
    patch "/users/#{@user.id}/posts/#{record.id}", params: { post: { title: "New title" } }
    assert_redirected_to "/users/#{@user.id}/posts"
    assert_equal "New title", record.reload.title
  end

  test "update with invalid params re-renders with 422" do
    record = Post.create!(title: "Valid", user: @user, body: "Body")
    patch "/users/#{@user.id}/posts/#{record.id}", params: { post: { title: "" } }
    assert_response :unprocessable_entity
    assert_select "form.l-ui-form"
    assert_select ".l-ui-form__errors"
  end

  # -- destroy --

  test "destroy removes record and redirects to index" do
    record = Post.create!(title: "Doomed", user: @user, body: "Body")
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
    record = Post.create!(title: "Protected", user: @user, body: "Body")
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

  test "destroy handles foreign-key violation gracefully" do
    record = Post.create!(title: "Locked", user: @user, body: "Body")
    Post.singleton_class.attr_accessor :_raise_fk_on_destroy
    fk_module = Module.new
    fk_module.module_eval do
      define_method(:destroy) do
        if self.class._raise_fk_on_destroy
          raise ActiveRecord::InvalidForeignKey, "fk constraint violation"
        else
          super()
        end
      end
    end
    Post.prepend(fk_module)
    Post._raise_fk_on_destroy = true
    begin
      assert_no_difference "Post.count" do
        delete "/users/#{@user.id}/posts/#{record.id}"
      end
      assert_redirected_to "/users/#{@user.id}/posts"
      follow_redirect!
      assert_select ".l-ui-notice--warning", /depend/i
    ensure
      Post._raise_fk_on_destroy = false
    end
  end

  test "destroy works without fields" do
    record = Post.create!(title: "Hello", user: @user, body: "Body")
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
    Post.create!(title: "My post", user: @user, body: "Body")
    Post.create!(title: "Their post", user: other_user, body: "Body")

    get "/users/#{@user.id}/posts"
    assert_response :success
    assert_select "th[scope='row']", text: "My post"
    assert_select "th[scope='row']", text: "Their post", count: 0
  end

  test "edit for post belonging to different user returns 404" do
    other_user = User.create!(email: "other@test.com", name: "Other", password: "password1234", password_confirmation: "password1234")
    theirs = Post.create!(title: "Their post", user: other_user, body: "Body")

    get "/users/#{@user.id}/posts/#{theirs.id}/edit"
    assert_response :not_found
  end

  # -- standalone posts (no user scoping) --

  test "standalone index shows all posts regardless of user" do
    other_user = User.create!(email: "other@test.com", name: "Other", password: "password1234", password_confirmation: "password1234")
    Post.create!(title: "My post", user: @user, body: "Body")
    Post.create!(title: "Their post", user: other_user, body: "Body")

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
    record = Post.create!(title: "Gone", user: @user, body: "Body")
    assert_difference "Post.count", -1 do
      delete "/posts/#{record.id}"
    end
    assert_redirected_to "/posts"
  end

  # -- @page_title --

  test "index sets @page_title to pluralized model name" do
    get "/posts"
    assert_select "title", text: /Posts/
  end

  test "show sets @page_title to record's primary column" do
    record = Post.create!(title: "Memorable", user: @user, body: "Body")
    get "/posts/#{record.id}"
    assert_select "title", text: /Memorable/
  end

  test "new sets @page_title to 'New <Model>'" do
    get "/posts/new"
    assert_select "title", text: /New Post/
  end

  test "edit sets @page_title to 'Edit <record label>'" do
    record = Post.create!(title: "Memorable", user: @user, body: "Body")
    get "/posts/#{record.id}/edit"
    assert_select "title", text: /Edit Memorable/
  end
end
