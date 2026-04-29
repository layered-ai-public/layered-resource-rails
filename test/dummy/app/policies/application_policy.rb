class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?    = false
  def show?     = false
  def create?   = false
  def new?      = create?
  def update?   = false
  def edit?     = update?
  def destroy?  = false

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NoMethodError, "must override #resolve"
    end
  end
end
