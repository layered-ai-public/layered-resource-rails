class ApplicationController < ActionController::Base
  # Find the gem spec
  GEM_SPEC = Gem.loaded_specs.values.find { |s|
    s.full_gem_path == Layered::ManagedResource::Engine.root.to_s
  }.freeze

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes if respond_to?(:stale_when_importmap_changes)

  # Configure permitted parameters for Devise
  before_action :configure_permitted_parameters, if: :devise_controller?

  # Set the page meta tags
  before_action :set_meta_tags

  # Expose the gem spec
  def gem_spec
    GEM_SPEC
  end
  helper_method :gem_spec

  def set_meta_tags
    @page_title = "#{gem_spec.name} (v#{gem_spec.version.to_s})"
    @page_description = gem_spec.description
  end

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
  end
end
