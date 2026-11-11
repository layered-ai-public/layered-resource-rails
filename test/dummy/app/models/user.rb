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

  # Searched by UserOptionsController's remote combobox endpoint
  def self.ransackable_attributes(auth_object = nil)
    %w[name email]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end
end
