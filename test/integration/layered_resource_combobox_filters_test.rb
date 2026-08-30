require "test_helper"

# Unit coverage for the descriptor keys behind the combobox filter control.
class LayeredResourceComboboxFiltersDslTest < ActiveSupport::TestCase
  def resource_with(*entries)
    Class.new(Layered::Resource::Base) do
      define_singleton_method(:name) { "AnonPostResource" }
      model Post
      columns [{ attribute: :title }]
      filters(*entries)
    end
  end

  test "an inferred select records that its control was not declared" do
    assert_not resource_with(:status).resolved_filters.first[:as_declared]
    assert_not resource_with(:user).resolved_filters.first[:as_declared]
  end

  test "a declared as: is recorded so the control stays pinned" do
    assert resource_with(status: { as: :select }).resolved_filters.first[:as_declared]
  end

  # An enum/belongs_to filter infers `as: :select`, so a declared `:combobox`
  # has to win over the inference while keeping the same predicate.
  test "as: combobox overrides the inferred select control but not its predicate" do
    f = resource_with(user: { as: :combobox }).resolved_filters.first

    assert_equal :combobox, f[:as]
    assert_equal :in, f[:predicate]
    assert_equal ["user_id_in"], f[:param_keys]
    assert f[:multiple]
  end

  test "as: combobox with multiple: false keeps the eq predicate" do
    f = resource_with(user: { as: :combobox, multiple: false }).resolved_filters.first

    assert_equal :combobox, f[:as]
    assert_equal :eq, f[:predicate]
  end

  test "combobox options pass through to the descriptor" do
    f = resource_with(user: { url: "/user_options", min_chars: 2, text: { empty: "None" } })
          .resolved_filters.first

    assert_equal "/user_options", f[:url]
    assert_equal 2, f[:min_chars]
    assert_equal({ empty: "None" }, f[:text])
  end

  # Write-side combobox options make no sense for a filter, which picks among
  # values that already exist.
  test "create/reorder options are not passed through" do
    f = resource_with(user: { create: true, reorder: true }).resolved_filters.first

    assert_nil f[:create]
    assert_nil f[:reorder]
  end

  # A url: on a plain string column has to promote it to a select-type filter,
  # or there'd be nothing for the fetched options to fill.
  test "a url: promotes a plain string column to a select-type filter" do
    f = resource_with(title: { url: "/titles" }).resolved_filters.first

    assert_equal :select, f[:as]
    assert_equal :in, f[:predicate]
  end
end

# Integration coverage: the threshold switch, the remote (`url:`) filter, and
# the round-trip of the blank value a combobox posts ahead of its selections.
class LayeredResourceComboboxFiltersIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @alice = User.create!(email: "alice@test.com", name: "Alice",
                         password: "password1234", password_confirmation: "password1234")
    @bob = User.create!(email: "bob@test.com", name: "Bob",
                        password: "password1234", password_confirmation: "password1234")
    @post = Post.create!(title: "Live post", user: @alice, status: :published, body: "Body")
  end

  # Enough users to take the author filter past the default threshold of 10,
  # whatever the database already holds.
  def many_users
    (1..12).map do |i|
      User.create!(email: "user#{i}@test.com", name: "User #{i}",
                   password: "password1234", password_confirmation: "password1234")
    end
  end

  def with_threshold(count)
    was = Layered::Resource.filter_combobox_threshold
    Layered::Resource.filter_combobox_threshold = count
    yield
  ensure
    Layered::Resource.filter_combobox_threshold = was
  end

  # -- the threshold --

  test "the threshold defaults to ten options" do
    assert_equal 10, Layered::Resource.filter_combobox_threshold
  end

  # Asserted against the real user count rather than a literal: the dummy app
  # is seeded, so what matters is that every option got a checkbox.
  test "an option list within the threshold stays a checkbox list" do
    with_threshold(User.count + 1) do
      get "/posts", params: { f: %w[user] }
    end

    assert_response :success
    assert_select "input[type=checkbox][name='q[user_id_in][]']", count: User.count
    assert_select ".l-ui-combobox", count: 0
  end

  test "the threshold is configurable" do
    with_threshold(1) do
      get "/posts", params: { f: %w[user] }
    end

    assert_response :success
    assert_select "input[type=checkbox][name='q[user_id_in][]']", count: 0
    assert_select ".l-ui-combobox"
  end

  test "an option list past the threshold switches to a combobox" do
    many_users

    get "/posts", params: { f: %w[user] }

    assert_response :success
    assert_select "input[type=checkbox][name='q[user_id_in][]']", count: 0
    assert_select ".l-ui-combobox" do
      assert_select "input[role='combobox']"
      assert_select "li[role='option'][data-value='#{@alice.id}']"
    end
  end

  # The tag row is unchanged by the control switch: the value still reads as
  # labels, not ids.
  test "a promoted filter's tag still shows its values by label" do
    many_users

    get "/posts", params: { q: { user_id_in: [@alice.id, @bob.id] } }

    assert_response :success
    assert_select "button[aria-label='Edit User filter']", text: /User: Alice, Bob/
  end

  test "a promoted filter's current values render as preselected tokens" do
    many_users

    get "/posts", params: { q: { user_id_in: [@alice.id] } }

    assert_response :success
    assert_select ".l-ui-combobox__token[data-value='#{@alice.id}']" do
      assert_select ".l-ui-tag__label", text: "Alice"
    end
  end

  # Multi-select posts through the combobox's own `[]`, so the `_in` predicate
  # still filters.
  test "a promoted multi-select still filters via the in predicate" do
    many_users

    get "/posts", params: { q: { user_id_in: [@alice.id] } }
    assert_select "tbody th", text: /Live post/

    get "/posts", params: { q: { user_id_in: [@bob.id] } }
    assert_select "tbody th", text: /Live post/, count: 0
  end

  test "a declared as: select keeps the checkbox list past the threshold" do
    many_users

    get "/remote/posts", params: { f: %w[status] }

    assert_response :success
    assert_select "input[type=checkbox][name='q[status_in][]']", count: 3
  end

  # -- single choice --

  test "a short single-choice list stays a menu of instant-apply links" do
    with_threshold(User.count + 1) do
      get "/single_author/posts", params: { f: %w[user] }
    end

    assert_response :success
    assert_select ".l-ui-combobox", count: 0
    assert_select "a.l-ui-popover__menu-item", text: "Alice"
  end

  # A single-choice combobox drops the `[]`, so the value lands as the scalar
  # `eq` expects rather than an array Ransack would have to cast.
  test "a promoted single-choice filter posts a scalar under the eq key" do
    with_threshold(1) do
      get "/single_author/posts", params: { f: %w[user] }
    end

    assert_response :success
    assert_select "a.l-ui-popover__menu-item", text: "Alice", count: 0
    assert_select ".l-ui-combobox[data-l-ui--combobox-multiple-value='false']" do
      assert_select "input[type=hidden][name='q[user_id_eq]']"
    end
  end

  test "a promoted single-choice filter still filters and labels its tag" do
    with_threshold(1) do
      get "/single_author/posts", params: { q: { user_id_eq: @alice.id } }
    end

    assert_response :success
    assert_select "button[aria-label='Edit User filter']", text: /User: Alice/
    assert_select "tbody th", text: /Live post/
  end

  # -- the blank a combobox posts ahead of its selections --

  # Clearing every token and applying submits `q[user_id_in][]=` alone. Ransack
  # prunes the blank from the query; the tag has to read as inactive too, and a
  # bare blank must not be mistaken for a value.
  test "a blank-only value reads as an inactive filter" do
    many_users

    get "/posts", params: { q: { user_id_in: [""] } }

    assert_response :success
    assert_select "button[aria-label='Edit User filter']", count: 0
    assert_select "tbody th", text: /Live post/
  end

  test "the blank is pruned from a value that has selections" do
    many_users

    get "/posts", params: { q: { user_id_in: ["", @alice.id] } }

    assert_response :success
    assert_select "button[aria-label='Edit User filter']", text: /User: Alice/
    assert_select "tbody th", text: /Live post/
  end

  # A defaulted filter is cleared by writing a blank rather than dropping the
  # key, so the blank a combobox posts must not let the default back in.
  test "clearing a defaulted filter through a blank does not re-apply it" do
    get "/pinned/posts", params: { q: { status_in: [""] } }

    assert_response :success
    assert_select "tbody th", text: /Live post/
  end

  # -- remote options --

  test "a url: filter renders a remote combobox regardless of list length" do
    get "/remote/posts", params: { f: %w[user] }

    assert_response :success
    assert_select ".l-ui-combobox[data-l-ui--combobox-url-value='/user_options']"
    assert_select ".l-ui-combobox[data-l-ui--combobox-min-chars-value='2']"
    # Remote options are fetched as the user types, never rendered up front.
    assert_select ".l-ui-combobox__listbox li[role='option']", count: 0
  end

  # A remote combobox has no collection in the browser to look a label up in,
  # so the selection has to arrive already labelled — read off the record.
  test "a remote filter's current value renders as a labelled token" do
    get "/remote/posts", params: { q: { user_id_in: [@alice.id] } }

    assert_response :success
    assert_select ".l-ui-combobox__token[data-value='#{@alice.id}']" do
      assert_select ".l-ui-tag__label", text: "Alice"
    end
    assert_select "button[aria-label='Edit User filter']", text: /User: Alice/
  end

  test "a remote filter still filters through its predicate" do
    get "/remote/posts", params: { q: { user_id_in: [@alice.id] } }
    assert_select "tbody th", text: /Live post/

    get "/remote/posts", params: { q: { user_id_in: [@bob.id] } }
    assert_select "tbody th", text: /Live post/, count: 0
  end

  test "the options endpoint answers with the matching users" do
    get "/user_options", params: { term: "Ali" }

    assert_response :success
    labels = JSON.parse(response.body)["options"].map { |o| o["label"] }
    assert_includes labels, "Alice"
    assert_not_includes labels, "Bob"
  end
end
