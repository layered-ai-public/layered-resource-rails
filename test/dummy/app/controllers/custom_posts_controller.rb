class CustomPostsController < Layered::Resource::ResourcesController
  skip_before_action :load_layered_member_record, only: [:deferred]

  def publish
    render plain: "published #{@record.id} #{@record.title}"
  end

  def archive_all
    render plain: "archived all (record nil: #{@record.nil?})"
  end

  def deferred
    render plain: "deferred (record nil: #{@record.nil?})"
  end
end
