# frozen_string_literal: true

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'valkyrie/shrine/version'

Gem::Specification.new do |spec|
  spec.name          = 'valkyrie-shrine'
  spec.version       = Valkyrie::Shrine::VERSION
  spec.license       = 'Apache-2.0'
  spec.authors       = ['Brendan Quinn']
  spec.email         = ['brendan-quinn@northwestern.edu']

  spec.summary       = 'Shrine storage adapter for Valkyrie'
  spec.homepage      = 'https://github.com/samvera-labs/valkyrie-shrine'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'aws-sdk-s3', '~> 1'
  spec.add_dependency 'shrine', '>= 2.0', '< 4.0'
  spec.add_dependency 'valkyrie', '> 1.0'

  spec.add_development_dependency 'bixby', '~> 2.0.0.pre.beta1'
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'coveralls', '~> 0.8.3'
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'actionpack'
end
