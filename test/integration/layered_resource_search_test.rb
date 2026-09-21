require "test_helper"

# The contract for the index search box. It searches as the term is typed, so
# the behaviour that used to be a Search button press now lives in a Stimulus
# controller - which this suite cannot drive. What it can pin down is the markup
# the controller is wired to, and the server-side behaviour underneath it.
class LayeredResourceSearchTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Author",
      password: "password1234",
      password_confirmation: "password1234"
    )
    @post = Post.create!(title: "Findable", body: "Body", user: @user)
  end

  # -- the buttons are gone --

  test "the index has no Search button to press" do
    get "/posts"
    assert_response :success
    assert_select "form[role=search] input[type=submit].l-ui-button--primary", false
  end

  test "the index has no separate Clear button beside the field" do
    get "/posts"
    assert_response :success
    assert_select "form[role=search] a.l-ui-button--outline", false
  end

  # A submit is still there for Enter and for a browser with no JavaScript; it
  # is just neither seen nor tabbed to.
  test "the form can still be submitted without JavaScript" do
    get "/posts"
    assert_response :success
    assert_select "form[role=search] input[type=submit].l-ui-sr-only[tabindex=-1]"
  end

  # -- searching as you type --

  test "the search field is wired to search as it is typed" do
    get "/posts"
    assert_response :success
    assert_select "input[data-l-ui--search-form-target=input]" do |inputs|
      action = inputs.first["data-action"]
      assert_includes action, "input->l-ui--search-form#search"
      assert_includes action, "keydown.esc->l-ui--search-form#clearSearch"
    end
  end

  test "a typed search replaces the history entry rather than pushing one" do
    get "/posts"
    assert_response :success
    assert_select "form[role=search][data-turbo-action=replace]"
  end

  # The frame keeps `advance`, so sort links and pagination still push state.
  test "the collection frame still advances" do
    get "/posts"
    assert_response :success
    assert_select "turbo-frame#layered_posts[data-turbo-action=advance]"
  end

  test "the search form targets the collection frame" do
    get "/posts"
    assert_response :success
    assert_select "form[role=search][data-turbo-frame=layered_posts]"
  end

  # -- the clear button --

  test "the clear button is hidden while there is nothing to clear" do
    get "/posts"
    assert_response :success
    assert_select "form[role=search] button.l-ui-search-control__clear[hidden]"
  end

  test "the clear button shows once a term has been searched for" do
    get "/posts", params: { q: { title_or_body_or_user_name_cont: "post" } }
    assert_response :success
    assert_select "form[role=search] button.l-ui-search-control__clear"
    assert_select "form[role=search] button.l-ui-search-control__clear[hidden]", false
  end

  test "the clear button has an accessible name" do
    get "/posts"
    assert_response :success
    assert_select "button.l-ui-search-control__clear span.l-ui-sr-only", text: "Clear search"
  end

  # -- announcing results --

  test "the result count is handed over to be announced" do
    get "/posts"
    assert_response :success
    count = css_select("form[role=search]").first["data-l-ui--search-form-count-value"]
    assert_equal Post.count.to_s, count
  end

  test "the count reflects the whole result set, not just the page" do
    12.times { |i| Post.create!(title: "Bulk #{i}", body: "Body", user: @user) }
    get "/posts"
    assert_response :success
    assert_select "form[role=search][data-l-ui--search-form-count-value='#{Post.count}']"
  end

  test "the announced count follows the search" do
    get "/posts", params: { q: { title_or_body_or_user_name_cont: "no-such-post-anywhere" } }
    assert_response :success
    assert_select "form[role=search][data-l-ui--search-form-count-value='0']"
  end

  # -- the search itself still works --

  test "searching narrows the collection" do
    Post.create!(title: "Excluded", body: "Body", user: @user)
    get "/posts", params: { q: { title_or_body_or_user_name_cont: "Findable" } }
    assert_response :success
    assert_select "td, th", text: "Findable"
    assert_select "td, th", text: "Excluded", count: 0
  end

  test "the searched-for term is rendered back into the field" do
    get "/posts", params: { q: { title_or_body_or_user_name_cont: "post" } }
    assert_response :success
    assert_select "input[data-l-ui--search-form-target=input][value=post]"
  end

  # -- accessibility of the control as a whole --

  test "the search box is a labelled search landmark" do
    get "/posts"
    assert_response :success
    assert_select "form[role=search][aria-label='Search posts']"
  end

  test "the field says that results update as you type" do
    get "/posts"
    assert_response :success
    input = css_select("input[data-l-ui--search-form-target=input]").first
    hint_id = input["aria-describedby"]
    assert hint_id.present?, "expected the field to be described by a hint"
    assert_select "##{hint_id}", text: "Results update as you type."
  end

  # -- resources without filters get the same control --

  test "a resource with no filters declared gets the same search control" do
    get "/users"
    assert_response :success
    assert_select "form[role=search][data-turbo-action=replace]"
    assert_select "form[role=search] button.l-ui-search-control__clear"
    assert_select "form[role=search] input[type=submit].l-ui-button--primary", false
  end

end
