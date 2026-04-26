require "test_helper"

class ManagedResourceColumnsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Author",
      password: "password1234",
      password_confirmation: "password1234"
    )
  end

  test "link option renders column value as badge link to nested managed resource" do
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
end
