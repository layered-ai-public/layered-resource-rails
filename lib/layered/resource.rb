require "layered-ui-rails"
require "ransack"
require "pagy"
require "layered/resource/version"
require "layered/resource/base"
require "layered/resource/routing"
require "layered/resource/engine"

module Layered
  module Resource
    mattr_accessor :before_action, default: nil
  end
end
