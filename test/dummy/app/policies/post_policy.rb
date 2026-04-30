class PostPolicy < ApplicationPolicy
  def index?    = user.present?
  def show?     = user.present? && record.user_id == user.id
  def create?   = user.present?
  def update?   = show?
  def destroy?  = show?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.nil?

      scope.where(user_id: user.id)
    end
  end
end
