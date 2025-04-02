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
          bucket.objects(prefix: [*prefix, id_prefix].join("/"))
                .map { |obj| (prefix.present? ? obj.key.sub(/^#{prefix}\//, "") : obj.key) }
        end
      end
    end
  end
end
