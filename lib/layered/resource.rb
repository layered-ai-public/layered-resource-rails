require "layered-ui-rails"
require "ransack"
require "pagy"
require "layered/resource/version"
require "layered/resource/base"
require "layered/resource/routing"
require "layered/resource/engine"

module Layered
  module Resource
    # Name of a controller method to call as a before_action on every
    # layered resource request. Typically set to an authentication method
    # like :authenticate_user!.
    mattr_accessor :authentication_method, default: nil

    # When true (the default), the controller calls Resource.configure_ransack
    # on the active resource's model the first time it's used. Set to false
    # if your app already manages ransackable_attributes / ransackable_associations
    # on the model and you don't want the gem to redefine them.
    mattr_accessor :auto_configure_ransack, default: true
  end
end
