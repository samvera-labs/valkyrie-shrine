# frozen_string_literal: true

require 'shrine'
require 'digest/md5'
require 'securerandom'

module Valkyrie
  module Storage
    class Shrine
      PROTOCOL = 'shrine://'

      attr_reader :shrine, :verifier, :path_generator, :identifier_prefix

      class IDPathGenerator
        def initialize(base_path: nil); end

        # @return [String]
        def generate(resource:, file:, original_filename:)
          # Because Valkyrie has to maintain compatibility with ActiveFedora via
          # the wings adapter, the file passed to #upload has to be saved before
          # its associated FileMetadata; this means that the resource provided
          # here is the parent FileSet rather than the FileMetadata object.  As
          # a result, when we upload derivatives (like thumbnails) we have to
          # pass the same resource as for the original file.  If we relied on
          # the resource.id to generate the ID for the StreamFile here, that
          # would result in derivative uploads overwriting their originals.
          # Thus we use a UUID, prefixed by the resource ID.
          "#{resource.id}/#{SecureRandom.uuid}"
        end
      end

      class DelayedDownload
        attr_reader :shrine, :id
        def initialize(shrine, id)
          @shrine = shrine
          @id = id
        end

        def file
          @file ||= shrine.open(id)
        end

        def method_missing(meth_name, *args, &block)
          return super unless file.respond_to?(meth_name)
          file.send(meth_name, *args, &block)
        end

        def respond_to_missing?(meth_name, include_private = false)
          file.respond_to?(meth_name) || super
        end
      end

      def initialize(shrine_storage, verifier = nil, path_generator = IDPathGenerator, identifier_prefix: nil)
        @path_generator = path_generator.new(base_path: "")
        @shrine = shrine_storage
        @identifier_prefix = identifier_prefix
        if verifier.nil?
          try_to_find_verifier
        else
          @verifier = verifier
        end
      end

      # Upload a file via the Shrine storage upload implementation
      # @param file [IO]
      # @param original_filename [String]
      # @param resource [Valkyrie::Resource]
      # @return [Valkyrie::StorageAdapter::StreamFile]
      # @raise Valkyrie::Shrine::IntegrityError if #verify_checksum is defined
      #   on the shrine object and the file and result digests do not match
      def upload(file:, original_filename:, resource:, **upload_options)
        # S3 adapter validates options, so we have to remove this one used in
        # the shared specs.
        upload_options.delete(:fake_upload_argument)
        identifier = path_generator.generate(resource: resource, file: file, original_filename: original_filename).to_s
        shrine.upload(file, identifier, **upload_options)
        find_by(id: "#{protocol_with_prefix}#{identifier}").tap do |result|
          if verifier
            raise Valkyrie::Shrine::IntegrityError unless verifier.verify_checksum(file, result)
          end
        end
      end

      # Return the file associated with the given identifier
      # @param id [Valkyrie::ID]
      # @return [Valkyrie::StorageAdapter::StreamFile]
      # @raise Valkyrie::StorageAdapter::FileNotFound if nothing is found
      def find_by(id:)
        raise Valkyrie::StorageAdapter::FileNotFound unless shrine.exists?(shrine_id_for(id))
        Valkyrie::StorageAdapter::StreamFile.new(id: Valkyrie::ID.new(id.to_s), io: DelayedDownload.new(shrine, shrine_id_for(id)))
      rescue Aws::S3::Errors::NoSuchKey
        raise Valkyrie::StorageAdapter::FileNotFound
      end

      # @param id [Valkyrie::ID]
      # @return [Boolean] true if this adapter can handle this type of identifier
      def handles?(id:)
        id.to_s.start_with?(protocol_with_prefix)
      end

      # Delete the file in S3 associated with the given identifier.
      # @param id [Valkyrie::ID]
      def delete(id:)
        shrine.delete(shrine_id_for(id))
      end

      # @param feature [Symbol] Feature to test for.
      # @return [Boolean] true if the adapter supports the given feature
      def supports?(_feature)
        false
      end

      private

        def try_to_find_verifier
          class_const = shrine.class.name.split(/::/).last.to_sym
          @verifier = Valkyrie::Shrine::Checksum.const_get(class_const).new if Valkyrie::Shrine::Checksum.const_defined?(class_const)
        end

        def shrine_id_for(id)
          id.to_s.sub(/^#{protocol_with_prefix}/, '')
        end

        def protocol_with_prefix
          [identifier_prefix, PROTOCOL].compact.join("-")
        end
    end
  end
end
