require_relative "lib/layered/managed_resource/version"

Gem::Specification.new do |spec|
  spec.name        = "layered-managed-resource-rails"
  spec.version     = Layered::ManagedResource::VERSION
  spec.authors     = [ "layered.ai" ]
  spec.email       = [ "support@layered.ai" ]
  spec.homepage    = "https://www.layered.ai"
  spec.description = "A convention-over-configuration CRUD engine for Rails 8+, built on layered-ui-rails. Provides auto-generated index, create, edit, and destroy interfaces with Ransack search and Pagy pagination."
  spec.summary     = "CRUD scaffolding engine for Rails, powered by layered-ui-rails."
  spec.license     = "Apache-2.0"

  spec.required_ruby_version = ">= 3.2.0"

  # Metadata
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/layered-ai-public/layered-managed-resource-rails"
  spec.metadata["bug_tracker_uri"] = "https://github.com/layered-ai-public/layered-managed-resource-rails/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Files
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,lib}/**/*", "LICENSE", "README.md", "Rakefile"]
      .reject { |f| File.basename(f) == ".DS_Store" }
  end
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "concurrent-ruby", ">= 1.0"
  spec.add_dependency "layered-ui-rails", "~> 0.3"
  spec.add_dependency "pagy", "~> 43.2"
  spec.add_dependency "rails", "~> 8.0"
  spec.add_dependency "ransack", "~> 4.0"

  spec.add_development_dependency "devise", "~> 5.0"
  spec.add_development_dependency "importmap-rails", "~> 2.0"
  spec.add_development_dependency "propshaft", "~> 1.0"
  spec.add_development_dependency "puma", "~> 7.0"
  spec.add_development_dependency "sqlite3", "~> 2.0"
  spec.add_development_dependency "stimulus-rails", "~> 1.0"
  spec.add_development_dependency "turbo-rails", "~> 2.0"
end
