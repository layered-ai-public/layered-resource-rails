require "test_helper"

class LayeredResourceRansackTest < ActiveSupport::TestCase
  # Use fresh anonymous classes for each test so configure_ransack's
  # per-model "configured" flag doesn't bleed between tests or interfere
  # with the real Post/User models used by the integration suite.
  def build_model(extra_class_methods = {})
    Class.new do
      define_singleton_method(:column_names) { ["id", "title"] }
      define_singleton_method(:reflect_on_all_associations) { |_kind| [] }
      define_singleton_method(:ransackable_attributes) { |_a = nil| ["pre_existing"] }
      define_singleton_method(:ransackable_associations) { |_a = nil| ["pre_existing_assoc"] }
      extra_class_methods.each { |name, body| define_singleton_method(name, &body) }
    end
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
end
