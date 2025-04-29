# frozen_string_literal: true

require "shrine/storage/s3"

module Valkyrie
  module Shrine
    module Storage
      class S3 < ::Shrine::Storage::S3
        # List objects that are starting with a given prefix.
        # This is helpful for versioned files that have a common file identifier.
        # Need to make sure to combine with storage prefix.
        #    list_objects(id_prefix: "some/object/id")
        # @param id_prefix [String] - object's id that starts with
        # @return [Array(Aws::S3::Object)]
        def list_objects(id_prefix:)
          aws_prefix = [*prefix, id_prefix].join("/")
          bucket.objects(prefix: aws_prefix)
        end

        # List objects id's that are starting with a given prefix.
        # This is helpful for versioned files that have a common file identifier.
        # Need to make sure to combine with storage prefix.
        #    list_object_ids(id_prefix: "some/object/id")
        # @param id_prefix [String] - object's id that starts with
        # @return [Array(String)]
        def list_object_ids(id_prefix:)
          objects = list_objects(id_prefix: id_prefix)
          object_ids_for(objects)
        end

        # Move a file to a another location.
        # @param id [String] - the id of the source file
        # @param destination_id [String] - the id of the destination file
        # @param destination_bucket [String] - the bucket name of the destination
        # @return [String]
        def move_to(id:, destination_id:, destination_bucket: bucket.name)
          source_object = Aws::S3::Object.new(bucket.name, object_key(id), client: client)
          destination_key = "#{destination_bucket}/#{object_key(destination_id)}"
          source_object.move_to(destination_key)
          destination_key
        end

        # Deletes all objects in fewest requests possible.
        # @see +super#delete_objects(objects)+.
        # @return [Array(string)] List of object id's that are deleted
        def delete_objects(objects)
          super
          object_ids_for(objects)
        end

        private

          # @ return list of object id's
          # @param objects [Array(Aws::S3::Object)]
          def object_ids_for(objects)
            keys = objects.map(&:key)
            return keys if prefix.blank?

            keys.map { |k| k.delete_prefix("#{prefix}/") }
          end
      end
    end
  end
end
