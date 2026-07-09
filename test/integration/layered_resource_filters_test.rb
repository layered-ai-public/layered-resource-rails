require "test_helper"

# Unit coverage for the `filters` DSL inference and the Ransack allowlist it
# produces. Uses the real Post model (which has a `status` enum, a `featured`
# boolean, a `created_at` datetime, a `comments_count` integer, and a
# `belongs_to :user`) so the column-type inference is exercised end to end.
class LayeredResourceFiltersDslTest < ActiveSupport::TestCase
  def resource_with(*entries)
    Class.new(Layered::Resource::Base) do
      define_singleton_method(:name) { "AnonPostResource" }
      model Post
      columns [{ attribute: :title }]
      filters(*entries)
    end
  end

  test "infers a multi-select from an enum column with DB values" do
    f = resource_with(:status).resolved_filters.first
    assert_equal :status, f[:attribute]
    assert_equal :status, f[:ransack_attribute]
    assert_equal :select, f[:as]
    assert_equal :in, f[:predicate]
    assert f[:multiple]
    assert_equal [["Draft", 0], ["Published", 1], ["Archived", 2]], f[:collection]
  end

  test "multiple: false opts a select into single-choice eq" do
    f = resource_with(status: { multiple: false }).resolved_filters.first
    assert_equal :eq, f[:predicate]
    assert_not f[:multiple]
    assert_equal ["status_eq"], f[:param_keys]
  end

  test "infers a boolean control from a boolean column" do
    f = resource_with(:featured).resolved_filters.first
    assert_equal :boolean, f[:as]
    assert_equal :eq, f[:predicate]
  end

  test "infers a date range from a datetime column" do
    f = resource_with(:created_at).resolved_filters.first
    assert_equal :date_range, f[:as]
    assert_equal({ from: :gteq, to: :lteq }, f[:predicates])
  end

  test "infers a number range from an integer column" do
    f = resource_with(:comments_count).resolved_filters.first
    assert_equal :range, f[:as]
    assert_equal({ from: :gteq, to: :lteq }, f[:predicates])
  end

  test "infers a multi-select keyed on the foreign key for a belongs_to" do
    f = resource_with(:user).resolved_filters.first
    assert_equal :user, f[:attribute]
    assert_equal :user_id, f[:ransack_attribute]
    assert_equal :select, f[:as]
    assert_equal :in, f[:predicate]
    assert f[:multiple]
    assert_equal Post.reflect_on_association(:user), f[:reflection]
  end

  test "a string column defaults to a contains filter, or a select with a collection" do
    assert_equal :string, resource_with(:title).resolved_filters.first[:as]
    assert_equal :cont, resource_with(:title).resolved_filters.first[:predicate]

    with_collection = resource_with(title: { collection: %w[Alpha Beta] }).resolved_filters.first
    assert_equal :select, with_collection[:as]
  end

  test "an explicit options hash overrides the inferred control and collection" do
    f = resource_with(status: { collection: %w[draft live] }).resolved_filters.first
    assert_equal :select, f[:as]
    assert_equal %w[draft live], f[:collection]
  end

  test "filter_attributes lists the own-model columns to allowlist" do
    resource = resource_with(:status, :featured, :created_at, :comments_count, user: {})
    assert_equal %w[status featured created_at comments_count user_id], resource.filter_attributes
  end

  test "filters are inherited by resource subclasses" do
    parent = resource_with(:status)
    child = Class.new(parent) { define_singleton_method(:name) { "ChildPostResource" } }
    assert_equal :status, child.resolved_filters.first[:attribute]
  end

  test "carries pinned, default, and param keys through the descriptor" do
    f = resource_with(status: { pinned: true, default: 1 }).resolved_filters.first
    assert f[:pinned]
    assert_equal 1, f[:default]
    assert_equal ["status_in"], f[:param_keys]

    range = resource_with(:created_at).resolved_filters.first
    assert_not range[:pinned]
    assert_nil range[:default]
    assert_equal %w[created_at_gteq created_at_lteq], range[:param_keys]
  end

  test "filter attributes are folded into the resource's ransackable allowlist" do
    resource = resource_with(:status, user: {})
    resource.configure_ransack
    assert_includes Post.ransackable_attributes(resource), "status"
    assert_includes Post.ransackable_attributes(resource), "user_id"
  end
end

# Integration coverage: the dummy app's PostResource declares the full filter
# set, so /posts exercises the rendered filter bar and each predicate against
# real records.
class LayeredResourceFiltersIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @alice = User.create!(email: "alice@test.com", name: "Alice",
                          password: "password1234", password_confirmation: "password1234")
    @bob = User.create!(email: "bob@test.com", name: "Bob",
                        password: "password1234", password_confirmation: "password1234")

    @draft    = Post.create!(title: "Draft post",    user: @alice, status: :draft,     featured: false)
    @live     = Post.create!(title: "Live post",     user: @alice, status: :published, featured: true)
    @archived = Post.create!(title: "Archived post", user: @bob,   status: :archived,  featured: false)

    # Give comments_count and created_at deterministic, distinct values.
    @draft.update_columns(comments_count: 1, created_at: Time.utc(2026, 1, 1))
    @live.update_columns(comments_count: 5, created_at: Time.utc(2026, 6, 1))
    @archived.update_columns(comments_count: 9, created_at: Time.utc(2026, 12, 1))
  end

  # -- filter bar markup --

  test "the add-filter popover lists each unpinned filter as a link adding an unset chip" do
    get "/posts"
    assert_response :success

    # Status is pinned, so it renders as an always-shown chip instead of a
    # menu entry. Add-menu links are the ones adding an f[] pending marker
    # (the pinned chip's own value links share the menu-item class).
    add_links = css_select("a.l-ui-popover__menu-item").select { |a| a["href"].include?("f%5B%5D") }
    assert_equal ["Featured", "Created at", "Comments count", "User"], add_links.map { |a| a.text.strip }
    assert_select "button[aria-label='Edit Status filter']", text: /\AStatus\z/m
    assert_select "button.l-ui-button--small", text: /Add filter/

    # Picking a filter doesn't set a value, so no unpinned controls render at rest.
    assert_select "input[name='q[created_at_gteq]']", count: 0
    assert_select "button[aria-label='Edit Created at filter']", count: 0
  end

  test "an added filter renders as an unset chip holding its controls" do
    get "/posts", params: { f: %w[created_at user] }
    assert_response :success

    # The chip shows just the filter's name until a value is set.
    assert_select "button[aria-label='Edit Created at filter']", text: /\ACreated at\z/m
    assert_select "a[aria-label='Remove Created at filter']"

    # Its popover holds the controls.
    assert_select "input[name='q[created_at_gteq]']"
    assert_select "input[name='q[created_at_lteq]']"
    assert_select "input[type=checkbox][name='q[user_id_in][]']", count: 2

    # Pending filters leave the add menu; the rest stay.
    assert_select "a.l-ui-popover__menu-item", text: "Created at", count: 0
    assert_select "a.l-ui-popover__menu-item", text: "Featured"
  end

  test "a chip's value links apply the filter and keep its f[] entry for ordering" do
    get "/posts", params: { f: %w[featured user] }
    apply = css_select("a.l-ui-popover__menu-item")
              .map { |a| a["href"] }
              .find { |h| h.include?("q%5Bfeatured_eq%5D=true") }
    assert apply, "expected an instant-apply link for featured yes"
    assert_includes apply, "f%5B%5D=featured" # keeps its place in the row
    assert_includes apply, "f%5B%5D=user"     # the other chip survives

    # Only the chip's ✕ drops its f[] entry.
    remove = css_select("a[aria-label='Remove Featured filter']").first["href"]
    assert_not_includes remove, "f%5B%5D=featured"
    assert_includes remove, "f%5B%5D=user"
  end

  test "chips render pinned first, then URL-only filters, then added order" do
    # comments_count and featured were added (in that f[] order, featured now
    # set); created_at is active straight from the URL with no f[] entry.
    get "/posts", params: { f: %w[comments_count featured],
                            q: { featured_eq: "true", created_at_gteq: "2026-01-01" } }
    labels = css_select("button[popovertarget][aria-label^='Edit']").map { |b| b["aria-label"] }
    assert_equal ["Edit Status filter", "Edit Created at filter",
                  "Edit Comments count filter", "Edit Featured filter"], labels
  end

  test "an active filter renders as a chip with an edit popover and a remove link" do
    get "/posts", params: { q: { status_in: [1], featured_eq: "true" } }
    assert_response :success

    assert_select "button[aria-label='Edit Status filter']", text: /Status: Published/
    assert_select "button[aria-label='Edit Featured filter']", text: /Featured: Yes/
    assert_select "a[aria-label='Remove Featured filter']"
    # Pinned chips are always shown, so they carry no remove ✕.
    assert_select "a[aria-label='Remove Status filter']", count: 0

    # Active filters leave the add-filter menu.
    assert_select "a.l-ui-popover__menu-item", text: "Featured", count: 0
    assert_select "a.l-ui-popover__menu-item", text: "Created at"
  end

  test "a chip's remove link strips only its own filter, keeping the others" do
    get "/posts", params: { q: { status_in: [1], featured_eq: "true" } }
    remove = css_select("a[aria-label='Remove Featured filter']").first["href"]
    assert_includes remove, "status_in"
    assert_not_includes remove, "featured_eq"
  end

  test "range chips summarise their bounds" do
    get "/posts", params: { q: { created_at_gteq: "2026-05-01", created_at_lteq: "2026-07-01" } }
    assert_select "button[aria-label='Edit Created at filter']",
                  text: /Created at: 2026-05-01 – 2026-07-01/

    get "/posts", params: { q: { comments_count_gteq: "4" } }
    assert_select "button[aria-label='Edit Comments count filter']",
                  text: /Comments count: ≥ 4/
  end

  test "a multi-select chip lists the selected values" do
    get "/posts", params: { q: { user_id_in: [@alice.id, @bob.id] } }
    assert_select "button[aria-label='Edit User filter']", text: /User: Alice, Bob/

    get "/posts", params: { q: { status_in: [0, 1] } }
    assert_select "button[aria-label='Edit Status filter']", text: /Status: Draft, Published/
  end

  test "no active filters renders only pinned chips, none removable" do
    get "/posts"
    assert_response :success
    assert_select "[aria-label*='Remove']", count: 0
    assert_select "button[aria-label*='Edit']", count: 1 # the pinned Status chip
  end

  # -- composition: search, filters, and sort survive each other --

  test "the search form round-trips active filters and unset chips as hidden fields" do
    get "/posts", params: { q: { status_in: [1] }, f: %w[created_at] }
    assert_select "form input[type=hidden][name='q[status_in][]'][value='1']"
    assert_select "form input[type=hidden][name='f[]'][value='created_at']"
  end

  test "the search clear link drops the term but keeps filters" do
    get "/posts", params: { q: { status_in: [1], title_or_body_or_user_name_cont: "post" } }
    clear = css_select("a.l-ui-button--outline").find do |a|
      a.text.strip == "Clear" && !a["class"].include?("l-ui-button--small")
    end
    assert clear, "expected a search clear link"
    assert_includes clear["href"], "status_in"
    assert_not_includes clear["href"], "cont"
  end

  test "sort links keep the search term, filters, and unset chips" do
    get "/posts", params: { f: %w[created_at],
                            q: { status_in: [1], title_or_body_or_user_name_cont: "post" } }
    sort = css_select("th.l-ui-table__header-cell--sortable a").map { |a| a["href"] }.first
    assert sort, "expected a sortable header link"
    assert_includes sort, "q%5Bs%5D="
    assert_includes sort, "status_in"
    assert_includes sort, "cont%5D=post"
    assert_includes sort, "f%5B%5D=created_at"
  end

  test "pagination links keep filters and unset chips" do
    Post.first.user.tap do |author|
      16.times { |i| Post.create!(title: "Filler #{i}", user: author, status: :published) }
    end
    get "/posts", params: { f: %w[created_at], q: { status_in: [1] } }
    page_link = css_select(".l-ui-pagy-container a[href]").map { |a| a["href"] }.first
    assert page_link, "expected a pagination link"
    assert_includes page_link, "status_in"
    assert_includes page_link, "f%5B%5D=created_at"
  end

  test "filter forms carry the current search term and sort as hidden fields" do
    get "/posts", params: { q: { title_or_body_or_user_name_cont: "post", s: "title asc" } }
    # The pinned Status chip's popover form must round-trip both.
    assert_select "form input[type=hidden][name='q[s]'][value='title asc']"
    assert_select "form input[type=hidden][name='q[title_or_body_or_user_name_cont]'][value='post']"
    assert_select "input[type=checkbox][name='q[status_in][]']", count: 3
  end

  # -- filtering behaviour --

  test "filters by an enum multi-select" do
    get "/posts", params: { q: { status_in: [1] } }
    assert_response :success
    assert_select "tbody th", text: /Live post/
    assert_select "tbody th", text: /Draft post/, count: 0
    assert_select "tbody th", text: /Archived post/, count: 0

    get "/posts", params: { q: { status_in: [0, 1] } }
    assert_select "tbody th", text: /Draft post/
    assert_select "tbody th", text: /Live post/
    assert_select "tbody th", text: /Archived post/, count: 0
  end

  test "filters by a boolean" do
    get "/posts", params: { q: { featured_eq: "true" } }
    assert_response :success
    assert_select "tbody th", text: /Live post/
    assert_select "tbody th", text: /Draft post/, count: 0
  end

  test "filters by a date range" do
    get "/posts", params: { q: { created_at_gteq: "2026-05-01", created_at_lteq: "2026-07-01" } }
    assert_response :success
    assert_select "tbody th", text: /Live post/
    assert_select "tbody th", text: /Draft post/, count: 0
    assert_select "tbody th", text: /Archived post/, count: 0
  end

  test "filters by a number range" do
    get "/posts", params: { q: { comments_count_gteq: 4, comments_count_lteq: 6 } }
    assert_response :success
    assert_select "tbody th", text: /Live post/
    assert_select "tbody th", text: /Draft post/, count: 0
    assert_select "tbody th", text: /Archived post/, count: 0
  end

  test "filters by an association multi-select" do
    get "/posts", params: { q: { user_id_in: [@bob.id] } }
    assert_response :success
    assert_select "tbody th", text: /Archived post/
    assert_select "tbody th", text: /Draft post/, count: 0
    assert_select "tbody th", text: /Live post/, count: 0
  end

  test "filters compose with the free-text search box" do
    get "/posts", params: { q: { title_or_body_or_user_name_cont: "post", status_in: [2] } }
    assert_response :success
    assert_select "tbody th", text: /Archived post/
    assert_select "tbody th", text: /Live post/, count: 0
  end

  test "a q param that is neither searched nor filtered is silently ignored" do
    # updated_at is a real column but not shown, searched, or filtered, so it
    # is not on the Ransack allowlist — the condition is dropped, not a 500.
    get "/posts", params: { q: { updated_at_eq: "2026-01-01" } }
    assert_response :success
    assert_select "tbody th", text: /Draft post/
    assert_select "tbody th", text: /Live post/
    assert_select "tbody th", text: /Archived post/
  end
end

# PinnedPostResource (at /pinned/posts) pins every filter — status with a
# default of published — exercising always-shown chips, default values, the
# explicit-blank clear that keeps a default from re-applying, and the
# add-filter button disappearing when nothing is left to add.
class LayeredResourceFiltersPinnedTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "pin@test.com", name: "Pin",
                         password: "password1234", password_confirmation: "password1234")
    @draft = Post.create!(title: "Draft post", user: @user, status: :draft)
    @live  = Post.create!(title: "Live post", user: @user, status: :published, featured: true)
  end

  test "a default value filters the index and shows on its chip" do
    get "/pinned/posts"
    assert_response :success
    assert_select "tbody th", text: /Live post/
    assert_select "tbody th", text: /Draft post/, count: 0
    assert_select "button[aria-label='Edit Status filter']", text: /Status: Published/
  end

  test "pinned chips have no remove link and suppress the add-filter button" do
    get "/pinned/posts"
    assert_select "button[aria-label='Edit Featured filter']", text: /\AFeatured\z/m
    assert_select "[aria-label*='Remove']", count: 0
    assert_select "button", text: /Add filter/, count: 0
  end

  test "clearing a defaulted filter writes an explicit blank so it stays cleared" do
    get "/pinned/posts"
    clear = css_select("a.l-ui-popover__menu-item--danger").find { |a| a.text.strip == "Clear" }
    assert clear, "expected a Clear link in the defaulted chip's popover"
    assert_equal "/pinned/posts?q%5Bstatus_in%5D=", clear["href"]

    # Following it disables the default rather than re-applying it.
    get clear["href"]
    assert_response :success
    assert_select "tbody th", text: /Draft post/
    assert_select "tbody th", text: /Live post/
    assert_select "button[aria-label='Edit Status filter']", text: /\AStatus\z/m
  end

  test "a default composes with explicitly set filters" do
    get "/pinned/posts", params: { q: { featured_eq: "true" } }
    assert_response :success
    assert_select "tbody th", text: /Live post/
    assert_select "tbody th", text: /Draft post/, count: 0
    assert_select "button[aria-label='Edit Status filter']", text: /Status: Published/
    assert_select "button[aria-label='Edit Featured filter']", text: /Featured: Yes/
  end
end
