# frozen_string_literal: true

module Valkyrie
  module Storage
    # The VersionedShrine adapter implements versioned storage on S3 that manages versions
    # through Shrine object id with a timestamp like shrine://[resource_id]/[UUID]_v-[timestamp].
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
        version_files(id: id)
          .map { |f| find_by(id: Valkyrie::ID.new(f)) }
      end

      # Retireve all file versions associated with the given identifier from S3
      # @param id [Valkyrie::ID]
      # @return [Array(String))] - list of file identifiers
      def version_files(id:)
        shrine.list_object_ids(id_prefix: shrine_id_for(id))
              .sort
              .reverse
              .map { |v| protocol_with_prefix + v }
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
        identifier = VersionId.new(Valkyrie::ID.new(identifier)).generate_version.string_id
        upload_file(file: file, identifier: identifier, **upload_options)
      end

      # Upload a new version file
      # @param id [Valkyrie::ID] ID of the Valkyrie::StorageAdapter::File to version.
      # @param file [IO]
      def upload_version(id:, file:, **upload_options)
        versioned_shrine_id = shrine_id_for(VersionId.new(id).generate_version.id)

        # For backward compatablity with files ingested in the past and we don't have to migrate it to versioned fies.
        #   If there is a file associated with the given identifier that is not a versioned file,
        #   simply convert it to a versioned file basing on last_modified time to keep all versioned files consistent.
        to_version_file(id: id) if shrine.exists?(shrine_id_for(id))

        upload_file(file: file, identifier: versioned_shrine_id, **upload_options)
      end

      # Delete the versioned file or delete all versions in S3 associated with the given identifier.
      # @param id [Valkyrie::ID]
      # @return [Array(Valkyrie::ID)] - file id's that are deleted.
      def delete(id:)
        version_id = VersionId.new(id)

        delete_ids = version_id.versioned? ? [id] : version_files(id: id).map { |f| Valkyrie::ID.new(f) }

        delete_ids.each do |delete_id|
          delete_id = version_id(delete_id).id # convert id with current reference.
          shrine_id_to_delete = shrine_id_for(delete_id)
          next unless shrine.exists?(shrine_id_to_delete)

          shrine.delete(shrine_id_to_delete)
        end
        delete_ids
      end

      # Find the file associated with the given version identifier
      #
      # Note: we need override it to use the latest version
      #   so that file characterization and derivative creation can use the latest file uploaded
      # @param id [Valkyrie::ID]
      # @return [Valkyrie::StorageAdapter::StreamFile]
      # @raise Valkyrie::StorageAdapter::FileNotFound if nothing is found
      def find_by(id:)
        id = if VersionId.new(id).versioned?
               id
             else
               Valkyrie::ID.new(version_files(id: id).first || id.to_s)
             end

        raise Valkyrie::StorageAdapter::FileNotFound unless shrine.exists?(shrine_id_for(id))
        Valkyrie::StorageAdapter::StreamFile.new(id: Valkyrie::ID.new(id.to_s.split(VersionId::VERSION_DELIMITER).first),
                                                 io: DelayedDownload.new(shrine, shrine_id_for(id)),
                                                 version_id: id)
      end

      # @return VersionId A VersionId value that's resolved a current reference,
      #   so we can access the `version_id` and current reference.
      def version_id(id)
        version_id = VersionId.new(id)
        return version_id unless version_id.versioned? && version_id.reference?
        id = Valkyrie::ID.new(id.to_s.split(VersionId::VERSION_DELIMITER).first)
        version_files(id: id).map { |f| VersionId.new(f) }
                             .first
      end

      # Convert a non-versioned file to a version file basing on its last_modified time.
      # @param id [Valkyrie::ID]
      def to_version_file(id:)
        shrine_id = shrine_id_for(id)
        last_modified = shrine.object(shrine_id).last_modified
        version_id = VersionId.new(id).generate_version(timestamp: last_modified).id
        source_object = Aws::S3::Object.new(shrine.bucket.name, shrine_id, client: shrine.client)
        source_object.move_to("#{shrine.bucket.name}/#{shrine_id_for(version_id)}")
      end

      # A class that holds a version id and methods for knowing things about it.
      # Examples of version ids in this adapter:
      #   * shrine://[resource_id]/[uuid]_v-current
      #   * shrine://[resource_id]/[uuid]_v-1694195675462560794
      class VersionId
        VERSION_DELIMITER = "_v-"
        CURRENT_VERSION = "current"

        attr_reader :id
        def initialize(id)
          @id = id
        end

        # Generate new version identifier basing on the given identifier, which could be the original file identifier like
        #   shrine://[resource_id]/[uuid], or a version identifier like shrine://[resource_id]/[uuid]_v-1694195675462560794.
        # @param timestamp [Time]
        # @return [VersionID]
        def generate_version(timestamp: nil)
          version_timestam = timestamp.respond_to?(:strftime) ? timestamp.strftime("%s%L") : timestamp || current_timestamp
          id_string = if versioned?
                        string_id.gsub(version, version_timestam)
                      else
                        string_id + VERSION_DELIMITER + version_timestam
                      end

          self.class.new(Valkyrie::ID.new(id_string))
        end

        def current_timestamp
          Time.now.utc.strftime("%s%L")
        end

        # @return [Boolean] Whether this id is referential (e.g. "current") or absolute (e.g. a timestamp)
        def reference?
          version == CURRENT_VERSION
        end

        def versioned?
          string_id.include?(VERSION_DELIMITER)
        end

        def version
          string_id.split(VERSION_DELIMITER).last
        end

        def string_id
          id.to_s
        end
      end
    end
  end
end
