# frozen_string_literal: true

module Valkyrie
  module Storage
    # The VersionedShrine adapter implements versioned storage on S3 through Shrine
    # the timestamp of the file's creation as part of the key for the file on S3
    # ([resource_id]/[UUID]_v-timestamp).
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
        return true if feature == :versions || feature == :version_deletion
        false
      end

      # Retireve all files versions with no deletion marker that are associated from S3.
      # @param id [Valkyrie::ID]
      # @return [Array(Valkyrie::Storage::VersionedShrine::VersionId)]
      def find_versions(id:)
        version_files(id: id).reject(&:deletion_marker?)
      end

      # Retireve all file versions associated with the given identifier from S3
      # @param id [Valkyrie::ID]
      # @return [Array(Valkyrie::Storage::VersionedShrine::VersionId)]
      def version_files(id:)
        shrine.list_object_ids(id_prefix: shrine_id_for(id))
              .sort
              .reverse
              .map { |v| VersionId.new(Valkyrie::ID.new(protocol_with_prefix + v)) }
      end

      # Upload a new version file
      # @param id [Valkyrie::ID] ID of the Valkyrie::StorageAdapter::File to version.
      # @param file [IO]
      def upload_version(id:, file:, **upload_options)
        # S3 adapter validates options, so we have to remove this one used in
        # the shared specs.
        upload_options.delete(:fake_upload_argument)

        version_identifier = shrine_id_for(VersionId.new(id).generate_version)
        shrine.upload(file, version_identifier, **upload_options)
        find_by(id: "#{protocol_with_prefix}#{version_identifier}").tap do |result|
          if verifier
            raise Valkyrie::Shrine::IntegrityError unless verifier.verify_checksum(file, result)
          end
          # TODO: move/change the original file with the basic file identifier to version file?
        end
      end

      # Delete the versioned file or delete all versions in S3 associated with the given identifier.
      # @param id [Valkyrie::ID]
      # @return [Array(Valkyrie::Storage::VersionedShrine::VersionId)] - versioned file's that are deleted.
      def delete(id:)
        version_id = VersionId.new(id)
        return [] if version_id.deletion_marker?

        delete_ids = if version_id.versioned?
                       [id]
                     else
                       find_versions(id: id).map(&:id)
                     end

        delete_ids.map do |delete_id|
          delete_id = version_id(delete_id).version_id # convert id with current reference.
          shrine.delete(shrine_id_for(delete_id))

          # Mark the object with deletion marker
          deletion_marker_id = Valkyrie::ID.new("#{delete_id}-#{VersionId::DELETION_MARKER}")
          shrine.object(shrine_id_for(deletion_marker_id)).put
          VersionId.new(deletion_marker_id)
        end
      end

      # Find the file associated with the given version identifier
      #
      # Note: we need override it to use the latest version
      #   so that file characterization and derivative creation can use the latest file uploaded
      # @param id [Valkyrie::ID]
      # @return [Valkyrie::StorageAdapter::StreamFile]
      # @raise Valkyrie::StorageAdapter::FileNotFound if nothing is found
      def find_by(id:)
        id = VersionId.new(id).versioned? ? id : (find_versions(id: id).first&.version_id || id)

        super
      end

      # @return VersionId A VersionId value that's resolved a current reference,
      #   so we can access the `version_id` and current reference.
      def version_id(id)
        version_id = VersionId.new(id)
        return version_id unless version_id.versioned? && version_id.reference?
        file_identifier = id.to_s.split(VersionId::VERSION_PREFIX).first
        find_versions(id: Valkyrie::ID.new(file_identifier)).first
      end

      # A class that holds a version id and methods for knowing things about it.
      # Examples of version ids in this adapter:
      #   * shrine://[resource_id]/[uuid]_v-current
      #   * shrine://[resource_id]/[uuid]_v-1694195675462560794
      #   * shrine://[resource_id]/[uuid]_v-1694195675462560794-deletionmarker
      class VersionId
        VERSION_PREFIX = "_v-"
        CURRENT_VERSION = "current"
        DELETION_MARKER = "deletionmarker"

        attr_reader :id
        def initialize(id)
          @id = id
        end

        # generate new version identifier basing on the current identifier,
        # which ould be a version identifier or the orignal form [file_set_id]/[uuid].
        def generate_version
          versioned? ? string_id.gsub(version, current_timestamp) : string_id.gsub(version, version + VERSION_PREFIX + current_timestamp)
        end

        def current_reference_id
          self.class.new(Valkyrie::ID.new(string_id.gsub(version, CURRENT_VERSION)))
        end

        def current_timestamp
          Time.now.utc.strftime("%s%L")
        end

        def deletion_marker?
          string_id.include?(DELETION_MARKER)
        end

        def current?
          version_files.first&.id == id
        end

        # @return [Boolean] Whether this id is referential (e.g. "current") or absolute (e.g. a timestamp)
        def reference?
          version == CURRENT_VERSION
        end

        def versioned?
          string_id.include?(VERSION_PREFIX)
        end

        def version_id
          id
        end

        def version
          string_id.split("/").last.split(VERSION_PREFIX).last
        end

        def string_id
          id.to_s
        end
      end
    end
  end
end
