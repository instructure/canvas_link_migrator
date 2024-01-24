# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "canvas_link_migrator"
  spec.version       = "1.0.3"
  spec.authors       = ["Mysti Lilla", "James Logan", "Sarah Gerard", "Math Costa"]
  spec.email         = ["mysti@instructure.com", "james.logan@instructure.com", "sarah.gerard@instructure.com", "luis.oliveira@instructure.com"]
  spec.summary       = "Instructure gem for migrating Canvas style rich content"

  spec.files         = Dir.glob("{lib,spec}/**/*") + %w[test.sh]
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport"
  spec.add_dependency "nokogiri"
  spec.add_dependency "rack"
  spec.add_dependency "addressable"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "byebug"
  spec.add_development_dependency "json"
  spec.add_development_dependency "rspec"
end
