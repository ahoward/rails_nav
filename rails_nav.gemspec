## rails_nav.gemspec
#

Gem::Specification::new do |spec|
  spec.name = "rails_nav"
  spec.version = "2.4.0"
  spec.platform = Gem::Platform::RUBY
  spec.summary = "rails_nav"
  spec.description = "description: rails_nav kicks the ass"

  spec.files =
["README", "Rakefile", "lib", "lib/rails_nav.rb", "rails_nav.gemspec"]

  spec.executables = []
  
  spec.require_path = "lib"

  spec.test_files = nil

  
    spec.add_dependency(*["rails_current", " >= 1.6"])
  
    spec.add_dependency(*["rails_helper", " >= 1.2"])
  

  spec.extensions.push(*[])

  spec.rubyforge_project = "codeforpeople"
  spec.author = "Ara T. Howard"
  spec.email = "ara.t.howard@gmail.com"
  spec.homepage = "https://github.com/ahoward/rails_nav"
end
