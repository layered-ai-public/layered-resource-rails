class Post < ApplicationRecord
  belongs_to :user, counter_cache: true

  delegate :name, to: :user, prefix: true

  validates :title, presence: true
end
