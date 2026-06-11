require "test_helper"

class LayeredResourceSearchPlaceholderTest < ActionDispatch::IntegrationTest
  test "index derives the placeholder from human attribute names" do
    get "/posts"
    assert_response :success
    assert_select "input[type=search], input[type=text]" do |inputs|
      assert inputs.any? { |i| i["placeholder"] == "Search by title, body, user name" },
             "expected derived placeholder, got: #{inputs.map { |i| i["placeholder"] }.inspect}"
    end
  end

  test "derived placeholder picks up activerecord.attributes i18n for association walks" do
    I18n.backend.store_translations(:en, activerecord: { attributes: { user: { name: "Identifier" } } })
    get "/posts"
    assert_response :success
    assert_select "input[placeholder='Search by title, body, user identifier']"
  ensure
    I18n.backend.reload!
  end

  test "search_placeholder overrides the derived default" do
    get "/users"
    assert_response :success
    assert_select "input[placeholder='Search by name or email address']"
  end

  test "search_placeholder is inherited by resource subclasses" do
    subclass = Class.new(UserResource)
    assert_equal "Search by name or email address", subclass.search_placeholder
  end

  test "derived placeholder uses i18n on the association name itself" do
    I18n.backend.store_translations(:en, activerecord: { attributes: { post: { user: "Owner" } } })
    get "/posts"
    assert_response :success
    assert_select "input[placeholder='Search by title, body, owner name']"
  ensure
    I18n.backend.reload!
  end
end
