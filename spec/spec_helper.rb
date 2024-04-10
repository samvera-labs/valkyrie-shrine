# frozen_string_literal: true

require 'bundler/setup'
require 'simplecov'
require 'coveralls'
require 'pry'

ENV['RACK_ENV'] = 'test'
ENV['RAILS_ENV'] = 'test'
Coveralls.wear!
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
  [
    SimpleCov::Formatter::HTMLFormatter,
    Coveralls::SimpleCov::Formatter
  ]
)
SimpleCov.start do
  add_filter 'spec'
  add_filter 'vendor'
end

require 'valkyrie/shrine'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

Dir[Pathname.new("./").join("spec", "support", "**", "*.rb")].sort.each { |file| require_relative file.gsub(/^spec\//, "") }
