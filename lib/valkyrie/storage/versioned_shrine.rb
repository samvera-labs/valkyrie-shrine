# frozen_string_literal: true

module Valkyrie
  module Storage
    # The VersionedShrine adapter implements versioned storage on S3 that manages versions
    # through Shrine object id with a timestamp like shrine://[resource_id]/[UUID]/v-[timestamp].
    #
    # Example to use VersionedShrine storage adapter:
    #    shrine_s3_options = {
    #      access_key_id: s3_access_key,
    #      bucket: s3_bucket,
    #      endpoint: s3_endpoint,
    #      force_path_style: force_path_style,
    #      region: s3_region,
    #      secret_access_key: s3_secret_key
    #    }
    #    Valkyrie::StorageAdapter.register(
    #      Valkyrie::Storage::VersionedShrine.new(Valkyrie::Shrine::Storage::S3.new(**shrine_s3_options)),
    #      :s3_repository
    #    )
    class VersionedShrine < Shrine
      # @param feature [Symbol] Feature to test for.
      # @return [Boolean] true if the adapter supports the given feature
      def supports?(feature)
        feature == :versions || feature == :version_deletion
      end

      # Retireve all files versions with no deletion marker that are associated from S3.
      # @param id [Valkyrie::ID]
      # @return [Array(Valkyrie::StorageAdapter::StreamFile)]
      def find_versions(id:)
        version_files(id: id).map { |f| find_by(id: f) }
      end

      # Retireve all file versions associated with the given identifier from S3
      # @param id [Valkyrie::ID]
      # @return [Array(Valkyrie::ID)] - list of file identifiers
      def version_files(id:)
        shrine.list_object_ids(id_prefix: shrine_id_for(id))
              .sort
              .reverse
              .map { |v| Valkyrie::ID.new(protocol_with_prefix + v) }
      end

      # Upload a file via the VersionedShrine storage adapter with a version id assigned.
      # @param file [IO]
      # @param original_filename [String]
      # @param resource [Valkyrie::Resource]
      # @return [Valkyrie::StorageAdapter::StreamFile]
      # @raise Valkyrie::Shrine::IntegrityError if #verify_checksum is defined
      #   on the shrine object and the file and result digests do not match
      def upload(file:, original_filename:, resource:, **upload_options)
        identifier = path_generator.generate(resource: resource, file: file, original_filename: original_filename)
        perform_upload(id: "#{protocol_with_prefix}#{identifier}", file: file, **upload_options)
      end

      # Upload a new version file
      # @param id [Valkyrie::ID] ID of the Valkyrie::StorageAdapter::File to version.
      # @param file [IO]
      def upload_version(id:, file:, **upload_options)
        # For backward compatablity with files ingested in the past and we don't have to migrate it to versioned fies.
        #   If there is a file associated with the given identifier that is not a versioned file,
        #   simply convert it to a versioned file basing on last_modified time to keep all versioned files consistent.
        migrate_to_versioned(id: id) if shrine.exists?(shrine_id_for(id))

        perform_upload(id: id, file: file, **upload_options)
      end

      # Upload a file with a version id assigned.
      # @param id [Valkyrie::ID] ID of the Valkyrie::StorageAdapter::File to version.
      # @param file [IO]
      # @return [Valkyrie::StorageAdapter::StreamFile]
      # @raise Valkyrie::Shrine::IntegrityError if #verify_checksum is defined
      def perform_upload(id:, file:, **upload_options)
        shrine_id = shrine_id_for(VersionId.new(id).new_version)
        upload_file(file: file, identifier: shrine_id, **upload_options)
      end

      # Delete the versioned file or delete all versions in S3 associated with the given identifier.
      # @param id [Valkyrie::ID]
      # @return [Array(Valkyrie::ID)] - file id's that are deleted.
      # @raise Valkyrie::StorageAdapter::FileNotFound if nothing is found
      def delete(id:)
        objects = objects_to_delete(id)
        raise Valkyrie::StorageAdapter::FileNotFound if objects.blank?

        shrine.delete_objects(objects)
              .map { |obj_id| Valkyrie::ID.new(protocol_with_prefix + obj_id) }
      end

      # Find the file associated with the given version identifier
      #
      # Note: we need override it to use the latest version
      #   so that file characterization and derivative creation can use the latest file uploaded
      # @param id [Valkyrie::ID]
      # @return [Valkyrie::StorageAdapter::StreamFile]
      # @raise Valkyrie::StorageAdapter::FileNotFound if nothing is found
      def find_by(id:)
        version_id = resolve_current(id)

        raise Valkyrie::StorageAdapter::FileNotFound unless version_id && shrine.exists?(shrine_id_for(version_id.id))
        Valkyrie::StorageAdapter::StreamFile.new(id: Valkyrie::ID.new(version_id.base_identifier),
                                                 io: DelayedDownload.new(shrine, shrine_id_for(version_id.id)),
                                                 version_id: version_id.id)
      end

      # @return VersionId A VersionId value that's resolved to a current version,
      #   so we can access the latest version with a base identifier that is not a version.
      def resolve_current(id)
        version_id = VersionId.new(id)
        return version_id if version_id.versioned?
        version_files = version_files(id: Valkyrie::ID.new(version_id.base_identifier))
        return nil if version_files.blank?
        VersionId.new(Valkyrie::ID.new(version_files.first))
      end

      # @param id [Valkyrie::ID]
      # @return [Array(Aws::S3::Object)] list of objects
      def objects_to_delete(id)
        shrine_id = shrine_id_for(id)
        version_id = VersionId.new(id)
        return shrine.list_objects(id_prefix: shrine_id).to_a unless version_id.versioned?

        shrine.exists?(shrine_id) ? [shrine.object(shrine_id)] : []
      end

      # Convert a non-versioned file to a version file basing on its last_modified time.
      # @param id [Valkyrie::ID]
      # @return [VerrsionId]
      def migrate_to_versioned(id:)
        shrine_id = shrine_id_for(id)
        last_modified = shrine.object(shrine_id).last_modified
        version_id = VersionId.new(id).new_version(timestamp: last_modified)
        shrine.move_to(id: shrine_id, destination_id: shrine_id_for(version_id))
        version_id
      end

      # A class that holds a version id and methods for knowing things about it.
      # Examples of version ids in this adapter:
      #   * shrine://[resource_id]/[uuid]/v-20250429142441274
      #
      # @note With '/' as path delimiter for versions like '/v-', there is an issue with MinIO
      #   that fails to list the version files if a file with a base identifier
      #   that is not a version exisits along with other versioned files associated with the base identifier.
      class VersionId
        VERSION_DELIMITER = "/v-"

        attr_reader :id
        def initialize(id)
          @id = id
        end

        # Create new version identifier basing on the given identifier, which could be the original file identifier like
        #   shrine://[resource_id]/[uuid], or a version identifier like shrine://[resource_id]/[uuid]/v-20250429142441274.
        # @param timestamp [Time]
        # @return [String]
        def new_version(timestamp: nil)
          version_timestamp = (timestamp&.utc || Time.now.utc).strftime("%Y%m%d%H%M%S%L")
          versioned? ? string_id.gsub(version, version_timestamp) : string_id + VERSION_DELIMITER + version_timestamp
        end

        def versioned?
          string_id.include?(VERSION_DELIMITER)
        end

        def version
          string_id.split(VERSION_DELIMITER).last
        end

        # @return [String] The base identifier that is not a version
        def base_identifier
          string_id.split(VERSION_DELIMITER).first
        end

        def string_id
          id.to_s
        end
      end
    end
  end
end
