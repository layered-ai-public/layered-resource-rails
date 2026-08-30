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

    # Attributes tried, in order, when labelling a record for which no
    # labelling attribute is known - a `belongs_to` filter's options, say,
    # where the associated model has no resource of its own to ask.
    LABEL_CANDIDATES = %i[name title label email].freeze

    class << self
      # Renders a record as a human label: the given `attribute` when it has a
      # value, else the first LABEL_CANDIDATES attribute that does, else the
      # record's own `to_s` when its model defines one, else "Model #id".
      #
      # The single implementation behind `Resource::Base.record_label` (which
      # supplies the resource's `label_attribute`), the controller's
      # `layered_record_label` helper, and the labels a select-type filter
      # gives the records in its collection.
      def record_label(record, attribute: nil)
        candidates = [attribute, *LABEL_CANDIDATES].compact.uniq

        candidates.each do |candidate|
          next unless record.respond_to?(candidate)

          value = record.public_send(candidate)
          return value.to_s if value.present?
        end

        # Kernel#to_s is the default `#<Post:0x...>`, which is no label at all;
        # a model that has defined its own is saying what it should read as.
        return record.to_s if record.method(:to_s).owner != Kernel

        "#{record.model_name.human} ##{record.id}"
      end
    end

    # When true (the default), the controller calls Resource.configure_ransack
    # on the active resource's model the first time it's used. Set to false
    # if your app already manages ransackable_attributes / ransackable_associations
    # on the model and you don't want the gem to redefine them.
    mattr_accessor :auto_configure_ransack, default: true

    # How many options a select-type filter may have before its control
    # switches from the plain list (checkboxes, or instant-apply links when
    # single-choice) to a type-ahead combobox. Short lists are quicker to scan
    # and click than to type into; long ones are unusable that way. A filter
    # that names its own `as:` is unaffected.
    mattr_accessor :filter_combobox_threshold, default: 10
  end
end
