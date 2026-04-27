require "test_helper"

class LayeredResourceInheritanceTest < ActionDispatch::IntegrationTest
  class SubPostResource < PostResource
    columns [
      { attribute: :title, primary: true },
      { attribute: :id, label: "ID" }
    ]
  end

  test "subclass inherits parent model when not overridden" do
    assert_equal Post, SubPostResource.model
  end

  test "subclass inherits parent search_fields when not overridden" do
    assert_equal PostResource.search_fields, SubPostResource.search_fields
    assert_equal [:title, :body], SubPostResource.search_fields
  end

  test "subclass inherits parent fields when not overridden" do
    assert_equal PostResource.fields, SubPostResource.fields
  end

  test "subclass overrides take effect without affecting the parent" do
    refute_equal PostResource.columns, SubPostResource.columns
    assert_includes SubPostResource.columns.map { |c| c[:attribute] }, :id
    refute_includes PostResource.columns.map { |c| c[:attribute] }, :id
  end
end
