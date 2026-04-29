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
