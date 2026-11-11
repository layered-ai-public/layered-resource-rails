class PostPolicy < ApplicationPolicy
  # Status rules give the index rows differing per-record answers: a
  # published post can still be edited but no longer deleted, and an
  # archived one is read-only.
  def index?    = user.present?
  def show?     = user.present? && record.user_id == user.id
  def create?   = user.present?
  def update?   = show? && !record.archived?
  def destroy?  = show? && record.draft?

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.nil?

      scope.where(user_id: user.id)
    end
  end
end
