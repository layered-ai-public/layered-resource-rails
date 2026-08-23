require "test_helper"

class LayeredResourceRecordLabelTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Alice",
      password: "password1234",
      password_confirmation: "password1234"
    )
  end

  class DefaultColumnsResource < Layered::Resource::Base
    model Post
  end

  class FirstColumnResource < Layered::Resource::Base
    model Post
    columns [{ attribute: :title }, { attribute: :body }]
  end

  class PrimaryColumnResource < Layered::Resource::Base
    model Post
    columns [{ attribute: :body }, { attribute: :title, primary: true }]
  end

  class DeclaredLabelResource < Layered::Resource::Base
    model Post
    columns [{ attribute: :comments_count, primary: true, as: :badge }]
    label_attribute :title
  end

  class SubResource < DeclaredLabelResource; end

  # -- label_attribute --

  test "defaults to the primary column" do
    assert_equal :title, PrimaryColumnResource.label_attribute
  end

  test "falls back to the first column when none is primary" do
    assert_equal :title, FirstColumnResource.label_attribute
  end

  test "falls back to :id with the default columns" do
    assert_equal :id, DefaultColumnsResource.label_attribute
  end

  test "an explicit declaration wins over the primary column" do
    assert_equal :title, DeclaredLabelResource.label_attribute
  end

  test "is inherited by a subclass" do
    assert_equal :title, SubResource.label_attribute
  end

  # -- record_label --

  test "labels a record by its label_attribute" do
    post = Post.new(title: "First post", body: "Body")

    assert_equal "First post", PrimaryColumnResource.record_label(post)
    assert_equal "First post", DeclaredLabelResource.record_label(post)
  end

  test "falls back to a candidate attribute when the label_attribute is blank" do
    # :id is the default label attribute and an unsaved record has none, so the
    # candidates are what is left to label it by.
    assert_equal "Untitled", DefaultColumnsResource.record_label(Post.new(title: "Untitled", body: "Body"))
  end

  test "falls back to the model name and id when nothing else has a value" do
    post = Post.create!(title: "Placeholder", user: @user, body: "Body")
    post.update_columns(title: "")

    assert_equal "Post ##{post.id}", FirstColumnResource.record_label(post)
  end

  # -- Layered::Resource.record_label, the shared implementation --

  test "labels a record with no resource by the first candidate attribute" do
    assert_equal "Alice", Layered::Resource.record_label(@user)
  end

  test "prefers a model's own to_s over the id fallback" do
    labelled = Class.new(Post) do
      def self.model_name = ActiveModel::Name.new(self, nil, "Post")
      def to_s = "a post that says so"
    end

    assert_equal "a post that says so", Layered::Resource.record_label(labelled.new)
  end

  # -- the helper the views and page titles use --

  test "the layered_record_label helper labels by the resource's label_attribute" do
    post = Post.create!(title: "Labelled by its title", user: @user, body: "Body")

    get "/posts/#{post.id}"

    assert_response :success
    assert_select "h1", text: "Labelled by its title"
  end
end
