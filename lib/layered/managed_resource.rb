require "layered-ui-rails"
require "ransack"
require "pagy"
require "layered/managed_resource/version"
require "layered/managed_resource/base"
require "layered/managed_resource/routing"
require "layered/managed_resource/engine"

module Layered
  module ManagedResource
    mattr_accessor :managed_resource_before_action, default: nil
  end
end
