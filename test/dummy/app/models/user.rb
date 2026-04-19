class User < ApplicationRecord
  # Includes
  devise :database_authenticatable,
    :validatable,
    :registerable,
    :confirmable,
    :recoverable,
    :lockable,
    :rememberable,
    :timeoutable,
    :trackable

  # Associations
  has_many :posts, dependent: :destroy

  # Callbacks
  after_create :confirm
end
