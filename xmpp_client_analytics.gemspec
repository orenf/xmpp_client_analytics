# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'xmpp_client_analytics/version'

Gem::Specification.new do |spec|
  spec.name          = "xmpp_client_analytics"
  spec.version       = VERSION
  spec.authors       = ["Oren Forer"]
  spec.email         = ["oren@junctionnetworks.com"]
  spec.description   = "this a description"
  spec.summary       = "this is a summary"
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
