require "test_helper"

class LayeredResourcePermittedParamsTest < ActiveSupport::TestCase
  class ScalarOnlyResource < Layered::Resource::Base
    model Post
    fields [{ attribute: :title }, { attribute: :body }]
  end

  class ArrayPermitResource < Layered::Resource::Base
    model Post
    fields [
      { attribute: :title },
      { attribute: :documents, permit: [] }
    ]
  end

  class NestedPermitResource < Layered::Resource::Base
    model Post
    fields [
      { attribute: :title },
      { attribute: :address_attributes, permit: [:street, :city] }
    ]
  end

  test "scalar fields produce a flat list of symbols" do
    assert_equal [:title, :body], ScalarOnlyResource.permitted_params
  end

  test "permit: [] produces a hash entry with an empty array (allows array values)" do
    assert_equal [:title, { documents: [] }], ArrayPermitResource.permitted_params
  end

  test "permit: with a key list produces a nested hash entry" do
    assert_equal [:title, { address_attributes: [:street, :city] }], NestedPermitResource.permitted_params
  end

  # `permit:` is strong-parameters configuration, and the form helper passes
  # any field key it does not recognise through to the input - where a stray
  # `permit` renders as an HTML attribute, or raises on a field type whose
  # helper takes named options only (`as: :combobox`).
  test "resolved_fields drops permit: while permitted_params keeps it" do
    resolved = ArrayPermitResource.resolved_fields

    assert_equal %i[title documents], resolved.map { |f| f[:attribute] }
    refute resolved.any? { |f| f.key?(:permit) }, "resolved_fields leaked permit: to the form layer"
    assert_equal [:title, { documents: [] }], ArrayPermitResource.permitted_params
  end

  test "resolved_fields drops permit: from a nested-hash field too" do
    resolved = NestedPermitResource.resolved_fields

    refute resolved.any? { |f| f.key?(:permit) }
    assert resolved.all? { |f| f.key?(:required) }, "dropping permit: cost the field its required flag"
  end

  test "splatting through ActionController::Parameters#permit accepts the mixed shape" do
    raw = ActionController::Parameters.new(
      title: "Hi",
      documents: %w[a.pdf b.pdf],
      address_attributes: { street: "1 Main", city: "Town", secret: "x" }
    )
    permitted = raw.permit(*NestedPermitResource.permitted_params, *ArrayPermitResource.permitted_params)

    assert_equal "Hi", permitted[:title]
    assert_equal %w[a.pdf b.pdf], permitted[:documents]
    assert_equal({ "street" => "1 Main", "city" => "Town" }, permitted[:address_attributes].to_unsafe_h)
  end
end
