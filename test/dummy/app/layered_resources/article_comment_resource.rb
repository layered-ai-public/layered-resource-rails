# Comments beneath an ArticleResource post, whose `:article_id` is the
# post's uid.
class ArticleCommentResource < CommentResource
  def self.scope(controller)
    Post.find_by!(uid: controller.params[:article_id]).comments
  end
end
