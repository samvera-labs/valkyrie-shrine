# frozen_string_literal: true

require 'valkyrie/shrine/version'
require 'valkyrie/storage/shrine'
require 'valkyrie/shrine/checksum/base'
require 'valkyrie/shrine/checksum/file_system'
require 'valkyrie/shrine/checksum/s3'
require 'valkyrie/shrine/storage/s3'
require 'valkyrie/storage/versioned_shrine'

module Valkyrie
  module Shrine
    class Valkyrie::Shrine::IntegrityError < StandardError; end
  end
end
