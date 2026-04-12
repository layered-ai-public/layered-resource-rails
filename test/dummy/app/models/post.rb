class Post < ApplicationRecord
  include Layered::ManagedResource::Resource

  belongs_to :user

  validates :title, presence: true

  def self.l_managed_resource_columns
    [
      { attribute: :title, primary: true },
      { attribute: :body },
      { attribute: :created_at, label: "Created" }
    ]
  end

  def self.l_managed_resource_search_fields
    [:title, :body]
  end

  def self.l_managed_resource_default_sort
    { attribute: :created_at, direction: :desc }
  end

  def self.l_managed_resource_fields
    [
      { attribute: :title, required: true },
      { attribute: :body, as: :text },
      { attribute: :user_id, as: :select, label: "Author", collection: -> { User.pluck(:email, :id) } }
    ]
  end
end
