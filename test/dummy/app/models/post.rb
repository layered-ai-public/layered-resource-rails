class Post < ApplicationRecord
  belongs_to :user, counter_cache: true
  has_many :comments, dependent: :destroy

  # Addresses a post by an unguessable token rather than its id, for
  # ArticleResource's `lookup_attribute :uid`.
  has_secure_token :uid

  enum :status, { draft: 0, published: 1, archived: 2 }

  delegate :name, to: :user, prefix: true

  validates :title, presence: true
  validates :body, presence: true
end
