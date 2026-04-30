require_relative "lib/layered/resource/version"

Gem::Specification.new do |spec|
  spec.name        = "layered-resource-rails"
  spec.version     = Layered::Resource::VERSION
  spec.authors     = [ "layered.ai" ]
  spec.email       = [ "support@layered.ai" ]
  spec.homepage    = "https://www.layered.ai"
  spec.description = "A convention-over-configuration CRUD engine for Rails 8+, built on the layered-ui-rails gem. Declare a resource class, mount it in routes.rb, and get index, new/create, edit/update, and destroy actions with clean default views, Ransack-powered search and sorting, and Pagy pagination. Override any controller or view when you need full control - generators are included to help you create custom controllers and views."
  spec.summary     = "Convention-over-configuration CRUD for Rails 8+ with Ransack and Pagy built in."
  spec.license     = "Apache-2.0"

  spec.required_ruby_version = ">= 3.3.0"

  # Metadata
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/layered-ai-public/layered-resource-rails"
  spec.metadata["bug_tracker_uri"] = "https://github.com/layered-ai-public/layered-resource-rails/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Files
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,lib,.claude/skills}/**/*", "NOTICE", "LICENSE", "TRADEMARK.md", "CLA.md", "CHANGELOG.md", "README.md", "AGENTS.md", "Rakefile"]
      .reject { |f| File.basename(f) == ".DS_Store" }
  end
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "concurrent-ruby", ">= 1.0"
  spec.add_dependency "layered-ui-rails", "~> 0.9"
  spec.add_dependency "pagy", "~> 43.2"
  spec.add_dependency "rails", "~> 8.0"
  spec.add_dependency "ransack", "~> 4.0"

  spec.add_development_dependency "devise", "~> 5.0"
  spec.add_development_dependency "importmap-rails", "~> 2.0"
  spec.add_development_dependency "propshaft", "~> 1.0"
  spec.add_development_dependency "pundit", "~> 2.4"
  spec.add_development_dependency "puma", "~> 7.0"
  spec.add_development_dependency "sqlite3", "~> 2.0"
  spec.add_development_dependency "stimulus-rails", "~> 1.0"
  spec.add_development_dependency "turbo-rails", "~> 2.0"
end
