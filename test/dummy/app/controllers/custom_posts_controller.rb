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

  def state
    render plain: "resource=#{@resource&.name} key=#{@layered_route_key} " \
                  "can_show=#{@resource_can_show} can_update=#{@resource_can_update} " \
                  "can_destroy=#{@resource_can_destroy} record=#{@record&.id}"
  end

  def collection_state
    render plain: "resource=#{@resource&.name} key=#{@layered_route_key} record_nil=#{@record.nil?}"
  end
end
