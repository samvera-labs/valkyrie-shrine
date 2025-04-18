# frozen_string_literal: true

require "shrine/storage/s3"

module Valkyrie
  module Shrine
    module Storage
      class S3 < ::Shrine::Storage::S3
        # List objects id's that are starting with a given prefix.
        # This is helpful for versioned files that have a common file identifier.
        # Need to make sure to combine with storage prefix.
        #    list_object_ids(id_prefix: "some/object/id")
        # @param id_prefix [String] - object's id that starts with
        # @return [Array(String)]
        def list_object_ids(id_prefix:)
          aws_prefix = [*prefix, id_prefix].join("/")
          keys = bucket.objects(prefix: aws_prefix).map(&:key)
          return keys if prefix.blank?

          keys.map { |k| k.delete_prefix("#{prefix}/") }
        end
      end
    end
  end
end
