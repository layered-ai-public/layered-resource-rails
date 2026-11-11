require "test_helper"

class LayeredResourceRowActionsTest < ActionDispatch::IntegrationTest
  setup do
    @author = User.create!(email: "author@test.com", name: "Author",
                           password: "password1234", password_confirmation: "password1234")
    @other = User.create!(email: "other@test.com", name: "Other",
                          password: "password1234", password_confirmation: "password1234")
    @own = Post.create!(title: "Own post", body: "Body", user: @author)
    @theirs = Post.create!(title: "Their post", body: "Body", user: @other)
    Comment.create!(post: @theirs, body: "Nice")
  end

  # -- default partial --

  test "the default menu is Edit and Delete" do
    get "/posts"

    assert_select "[aria-label='Actions for Own post'] ~ .l-ui-popover .l-ui-popover__menu" do
      assert_select "a[href='/posts/#{@own.id}/edit']", text: "Edit"
      assert_select "hr.l-ui-popover__menu-divider"
      assert_select "form[action='/posts/#{@own.id}'] button", text: "Delete"
    end
  end

  test "the default menu leaves out actions the route doesn't expose" do
    get "/deletable/users"

    assert_select ".l-ui-popover__menu" do
      assert_select "a", text: "Edit", count: 0
      assert_select "hr", count: 0
      assert_select "button", text: "Delete"
    end
  end

  test "the default menu shows the actions the policy permits" do
    sign_in @author
    get "/pundit/posts"

    assert_select "[aria-label='Actions for Own post'] ~ .l-ui-popover .l-ui-popover__menu" do
      assert_select "a", text: "Edit"
      assert_select "button", text: "Delete"
    end
  end

  test "an index-only resource without its own partial has no actions column" do
    get "/readonly/users"

    assert_select "th.l-ui-table__header-cell--action", count: 0
    assert_select "[aria-label^='Actions for']", count: 0
  end

  # -- resource's own partial --

  test "a resource's partial replaces the default menu, per record and per user" do
    sign_in @author
    get "/team_posts"

    assert_select "[aria-label='Actions for Own post'] ~ .l-ui-popover .l-ui-popover__menu" do
      assert_select "a", text: "Comments", count: 0
      assert_select "a[href='/team_posts/#{@own.id}/edit']", text: "Edit"
      assert_select "form[action='/team_posts/#{@own.id}'] button", text: "Delete"
      assert_select "a", text: /More by/, count: 0
    end

    assert_select "[aria-label='Actions for Their post'] ~ .l-ui-popover .l-ui-popover__menu" do
      assert_select "a[href='/users/#{@other.id}/posts/#{@theirs.id}/comments']", text: "Comments"
      assert_select "a[href='/users/#{@other.id}/posts']", text: "More by Other"
      assert_select "a", text: "Edit", count: 0
      assert_select "button", text: "Delete", count: 0
    end
  end

  test "the menu follows whoever is signed in" do
    sign_in @other
    get "/team_posts"

    assert_select "[aria-label='Actions for Own post'] ~ .l-ui-popover .l-ui-popover__menu" do
      assert_select "a[href='/users/#{@author.id}/posts']", text: "More by Author"
      assert_select "a", text: "Edit", count: 0
    end
    assert_select "[aria-label='Actions for Their post'] ~ .l-ui-popover .l-ui-popover__menu" do
      assert_select "a", text: "Edit"
      assert_select "button", text: "Delete"
    end
  end

  test "a resource's partial gives an index-only route an actions column" do
    sign_in @author
    get "/browse/team_posts"

    assert_select "th.l-ui-table__header-cell--action"
    assert_select "[aria-label='Actions for Their post'] ~ .l-ui-popover .l-ui-popover__menu" do
      assert_select "a", text: "Comments"
      assert_select "a", text: "More by Other"
    end
  end

  test "a row whose partial renders nothing gets no menu" do
    sign_in @author
    get "/browse/team_posts"

    # The author's own post has no comments, and Edit and Delete aren't
    # routed here, so its partial comes out empty.
    assert_select "[aria-label='Actions for Own post']", count: 0
    assert_select "tr th", text: "Own post"
  end
end
