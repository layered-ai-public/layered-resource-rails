class Post < ApplicationRecord
  belongs_to :user, counter_cache: true
  has_many :comments, dependent: :destroy

  delegate :name, to: :user, prefix: true

  validates :title, presence: true
end
