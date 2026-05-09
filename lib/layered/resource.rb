require "layered-ui-rails"
require "ransack"
require "pagy"
require "layered/resource/version"
require "layered/resource/base"
require "layered/resource/routing"
require "layered/resource/engine"

module Layered
  module Resource
    # Raised when `owned_by` resolves a nil owner without `allow_nil: true`.
    # Surfaces auth misconfiguration loudly instead of silently 404ing every
    # request.
    class MissingOwnerError < StandardError; end

    # When true (the default), the controller calls Resource.configure_ransack
    # on the active resource's model the first time it's used. Set to false
    # if your app already manages ransackable_attributes / ransackable_associations
    # on the model and you don't want the gem to redefine them.
    mattr_accessor :auto_configure_ransack, default: true
  end
end
