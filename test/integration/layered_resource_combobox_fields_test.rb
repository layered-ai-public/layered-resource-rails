require "test_helper"

class LayeredResourceComboboxFieldsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "author@test.com",
      name: "Alice",
      password: "password1234",
      password_confirmation: "password1234"
    )
  end

  class ExplicitTypeResource < Layered::Resource::Base
    model Post
    fields [{ attribute: :user_id, as: :number }]
  end

  class ExplicitCollectionResource < Layered::Resource::Base
    model Post
    fields [{ attribute: :user_id, collection: [["Only me", 1]] }]
  end

  class MultipleResource < Layered::Resource::Base
    model Post
    fields [{ attribute: :user_id, multiple: true }]
  end

  class PlainColumnResource < Layered::Resource::Base
    model Post
    fields [{ attribute: :title }, { attribute: :comments_count }]
  end

  # -- inference --

  test "a belongs_to foreign key infers a single-select combobox" do
    field = PostResource.resolved_fields.find { |f| f[:attribute] == :user_id }

    assert_equal :combobox, field[:as]
    assert_equal false, field[:multiple]
  end

  test "the inferred collection is a callable labelling each record" do
    field = PostResource.resolved_fields.find { |f| f[:attribute] == :user_id }
    collection = field[:collection]

    assert_respond_to collection, :call, "the collection should be resolved per request, not at boot"
    assert_includes collection.call, ["Alice", @user.id]
  end

  test "a declared as: opts out of the combobox" do
    field = ExplicitTypeResource.resolved_fields.first

    assert_equal :number, field[:as]
    assert_nil field[:collection]
  end

  test "a declared collection: replaces the options but keeps the control" do
    field = ExplicitCollectionResource.resolved_fields.first

    assert_equal :combobox, field[:as]
    assert_equal [["Only me", 1]], field[:collection]
  end

  test "a declared multiple: is not overridden" do
    assert_equal true, MultipleResource.resolved_fields.first[:multiple]
  end

  test "an ordinary column is left alone" do
    PlainColumnResource.resolved_fields.each do |field|
      assert_nil field[:as], "#{field[:attribute]} should not have inferred a control"
    end
  end

  # A belongs_to validates the presence of the association, not of the foreign
  # key the form posts, so the required flag has to resolve through it.
  test "a required belongs_to marks its foreign-key field required" do
    field = PostResource.resolved_fields.find { |f| f[:attribute] == :user_id }

    assert field[:required], "a required association should render a required picker"
  end

  # -- rendering --

  test "new renders the author picker as a single-select combobox" do
    get "/posts/new"

    assert_response :success
    assert_select ".l-ui-combobox[data-l-ui--combobox-multiple-value='false']" do
      assert_select "label.l-ui-label", text: /Author/
      assert_select "input[role='combobox']"
      assert_select "li[role='option'][data-value='#{@user.id}']" do
        assert_select ".l-ui-combobox__option-label", text: "Alice"
      end
    end
  end

  test "the picker posts the foreign key under the model's parameter name" do
    get "/posts/new"

    assert_response :success
    assert_select ".l-ui-combobox input[type='hidden'][name='post[user_id]']"
  end

  test "edit preselects the record's current author as a token" do
    post = Post.create!(title: "Hello", user: @user, body: "Body")

    get "/posts/#{post.id}/edit"

    assert_response :success
    assert_select ".l-ui-combobox__token[data-value='#{@user.id}']" do
      assert_select ".l-ui-tag__label", text: "Alice"
    end
  end

  test "creating through the form assigns the chosen author" do
    assert_difference "Post.count", 1 do
      post "/posts", params: { post: { title: "Chosen", body: "Body", user_id: @user.id } }
    end

    assert_equal @user, Post.find_by(title: "Chosen").user
  end
end
