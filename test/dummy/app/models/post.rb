class Post < ApplicationRecord
  belongs_to :user

  delegate :name, to: :user, prefix: true

  validates :title, presence: true
end
