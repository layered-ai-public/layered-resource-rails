require "test_helper"

class LayeredResourceRansackTest < ActiveSupport::TestCase
  # Use fresh anonymous classes for each test so configure_ransack's
  # per-model "configured" flag doesn't bleed between tests or interfere
  # with the real Post/User models used by the integration suite.
  def build_model(extra_class_methods = {})
    Class.new do
      define_singleton_method(:column_names) { ["id", "title"] }
      define_singleton_method(:reflect_on_all_associations) { |_kind = nil| [] }
      define_singleton_method(:ransackable_attributes) { |_a = nil| ["pre_existing"] }
      define_singleton_method(:ransackable_associations) { |_a = nil| ["pre_existing_assoc"] }
      extra_class_methods.each { |name, body| define_singleton_method(name, &body) }
    end
  end

  def build_reflection(name, klass)
    reflection = Object.new
    reflection.define_singleton_method(:name) { name }
    reflection.define_singleton_method(:polymorphic?) { false }
    reflection.define_singleton_method(:klass) { klass }
    reflection
  end

  def build_resource(model_class, columns: [{ attribute: :title }], search: [])
    Class.new(Layered::Resource::Base) do
      define_singleton_method(:name) { "AnonResource" }
      model model_class
      columns(columns)
      search_fields(search)
    end
  end

  test "preserves the model's prior ransackable_attributes for non-layered callers" do
    m = build_model
    r = build_resource(m)
    r.configure_ransack

    assert_equal ["pre_existing"], m.ransackable_attributes
    assert_equal ["pre_existing"], m.ransackable_attributes(Object)
    assert_equal ["pre_existing_assoc"], m.ransackable_associations
  end

  test "returns the resource's allowlist when called with its own resource as auth_object" do
    m = build_model
    r = build_resource(m, columns: [{ attribute: :title }], search: [:body])
    r.configure_ransack

    assert_equal ["title", "id", "body"], m.ransackable_attributes(r)
  end

  test "falls back to the original method when called by a different resource (cross-model walk)" do
    m = build_model
    r = build_resource(m)
    r.configure_ransack

    other_model = build_model
    other_resource = build_resource(other_model)

    assert_equal ["pre_existing"], m.ransackable_attributes(other_resource)
  end

  test "configure_ransack is idempotent per model regardless of which resource calls it first" do
    m = build_model
    r1 = build_resource(m, columns: [{ attribute: :title }])
    r2 = build_resource(m, columns: [{ attribute: :title }], search: [:extra])

    r1.configure_ransack
    r2.configure_ransack

    assert_equal ["title", "id"], m.ransackable_attributes(r1)
    assert_equal ["title", "id", "extra"], m.ransackable_attributes(r2)
  end

  # -- association-walking search fields (e.g. :user_name -> users.name) --

  def build_associated_pair
    author = build_model
    author.define_singleton_method(:column_names) { ["id", "name"] }
    parent = build_model
    reflection = build_reflection(:author, author)
    parent.define_singleton_method(:reflect_on_all_associations) { |_kind = nil| [reflection] }
    [parent, author]
  end

  test "association_search_fields resolves walk-shaped entries and skips own columns" do
    parent, author = build_associated_pair
    r = build_resource(parent, search: [:title, :author_name, :author_missing])

    assert_equal [{ association: "author", attribute: "name", klass: author }],
                 r.association_search_fields
  end

  test "association-walking search fields are excluded from the model's attribute allowlist" do
    parent, = build_associated_pair
    r = build_resource(parent, search: [:title, :author_name])
    r.configure_ransack

    assert_equal ["title", "id"], parent.ransackable_attributes(r)
  end

  test "association-walking search fields allowlist the association on the parent" do
    parent, = build_associated_pair
    r = build_resource(parent, search: [:author_name])
    r.configure_ransack

    # "pre_existing_assoc" survives because the stub's define_singleton_method
    # counts as a host-defined allowlist (singleton-class owner).
    assert_equal ["pre_existing_assoc", "author"], parent.ransackable_associations(r)
  end

  test "association-walking search fields allowlist the attribute on the associated model" do
    parent, author = build_associated_pair
    r = build_resource(parent, search: [:author_name])
    r.configure_ransack

    assert_equal ["pre_existing", "name"], author.ransackable_attributes(r)
    assert_equal ["pre_existing"], author.ransackable_attributes
    assert_equal ["pre_existing"], author.ransackable_attributes(Object)
  end

  test "self-referential walks allowlist the walked attribute on the model itself" do
    m = build_model
    m.define_singleton_method(:column_names) { ["id", "title", "slug"] }
    reflection = build_reflection(:parent, m)
    m.define_singleton_method(:reflect_on_all_associations) { |_kind = nil| [reflection] }
    r = build_resource(m, search: [:title, :parent_slug])
    r.configure_ransack

    assert_includes m.ransackable_associations(r), "parent"
    assert_includes m.ransackable_attributes(r), "slug"
  end

  test "host-defined ransackable_associations are unioned with association walks" do
    parent, = build_associated_pair
    # Simulate a host-defined override: redefine via def-style singleton so
    # the method owner is a Class (mirrors `def self.ransackable_associations`).
    parent.singleton_class.class_eval do
      def ransackable_associations(_a = nil)
        ["host_assoc"]
      end
    end
    r = build_resource(parent, search: [:author_name])
    r.configure_ransack

    assert_equal ["host_assoc", "author"], parent.ransackable_associations(r)
    assert_equal ["host_assoc"], parent.ransackable_associations
  end
end

class LayeredResourceAssociationSearchIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @alice = User.create!(email: "alice@test.com", name: "Alice",
                          password: "password1234", password_confirmation: "password1234")
    @bob = User.create!(email: "bob@test.com", name: "Bob",
                        password: "password1234", password_confirmation: "password1234")
    Post.create!(title: "First", user: @alice)
    Post.create!(title: "Second", user: @bob)
  end

  test "index filters by an association-walking search field" do
    get "/posts", params: { q: { title_or_body_or_user_name_cont: "Alice" } }
    assert_response :success
    assert_select "tbody th", text: /First/
    assert_select "tbody th", text: /Second/, count: 0
  end

  test "index still filters by the model's own search fields" do
    get "/posts", params: { q: { title_or_body_or_user_name_cont: "Second" } }
    assert_response :success
    assert_select "tbody th", text: /Second/
    assert_select "tbody th", text: /First/, count: 0
  end

  test "index sorts by an association-walking search field" do
    get "/posts", params: { q: { s: "user_name desc" } }
    assert_response :success
    # Bob's post ("Second") sorts before Alice's ("First") on users.name desc.
    assert_operator response.body.index("Second"), :<, response.body.index("First")
  end
end
