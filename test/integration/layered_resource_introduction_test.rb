require "test_helper"

class LayeredResourceIntroductionTest < ActionDispatch::IntegrationTest
  test "renders the resource's _introduction partial above the search area when present" do
    get "/posts"
    assert_response :success
    # Dummy app ships app/views/layered/posts/_introduction.html.erb.
    assert_select "#posts-introduction"
    # The introduction precedes the search/table turbo frame.
    body = response.body
    intro_at = body.index("posts-introduction")
    frame_at = body.index(%(id="layered_posts"))
    assert intro_at && frame_at && intro_at < frame_at,
           "expected introduction partial to render above the search/table turbo frame"
  end

  test "resources without an _introduction partial render no introduction" do
    get "/users"
    assert_response :success
    assert_select "#posts-introduction", count: 0
  end
end
