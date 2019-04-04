# frozen_string_literal: true

require 'shrine'
require 'digest/md5'

module Valkyrie
  module Storage
    class Shrine
      PROTOCOL = 'shrine://'

      attr_reader :shrine, :verifier, :path_generator

      class IDPathGenerator
        def initialize(base_path: nil)
          @base_path = base_path
        end

        def generate(resource:, file:, original_filename:)
          resource.id.to_s
        end
      end

      def initialize(shrine_storage, verifier = nil, path_generator = IDPathGenerator)
        @path_generator = path_generator.new(base_path: "")
        @shrine = shrine_storage
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
        identifier = path_generator.generate(resource: resource, file: file, original_filename: original_filename).to_s
        shrine.upload(file, identifier, **upload_options)
        find_by(id: "#{PROTOCOL}#{identifier}").tap do |result|
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
        Valkyrie::StorageAdapter::StreamFile.new(id: Valkyrie::ID.new(id.to_s), io: shrine.open(shrine_id_for(id)))
      rescue Aws::S3::Errors::NoSuchKey
        raise Valkyrie::StorageAdapter::FileNotFound
      end

      # @param id [Valkyrie::ID]
      # @return [Boolean] true if this adapter can handle this type of identifier
      def handles?(id:)
        id.to_s.start_with?(PROTOCOL)
      end

      # Delete the file in S3 associated with the given identifier.
      # @param id [Valkyrie::ID]
      def delete(id:)
        shrine.delete(shrine_id_for(id))
      end

      private

        def try_to_find_verifier
          class_const = shrine.class.name.split(/::/).last.to_sym
          @verifier = Valkyrie::Shrine::Checksum.const_get(class_const).new if Valkyrie::Shrine::Checksum.const_defined?(class_const)
        end

        def shrine_id_for(id)
          id.to_s.sub(/^#{PROTOCOL}/, '')
        end
    end
  end
end
