# frozen_string_literal:true

module Valkyrie
  module Shrine
    module Checksum
      class S3 < Base
        attr_reader :threshold, :part_size

        def self.digest_class
          Digest::MD5
        end

        def initialize(threshold: 15 * 1024 * 1024, part_size: 5 * 1024 * 1024)
          @threshold = threshold
          @part_size = part_size
        end

        def calculate_checksum(result)
          result.io.data[:object]&.data&.etag&.delete('"') ||
            checksum_for(result.io)
        end

        def checksum_for(io)
          io.rewind
          io.size < threshold ? simple_digest(io) : multipart_checksum(io)
        end

        private

          def multipart_checksum(io)
            parts = 0
            checksums = []
            while (chunk = io.read(part_size))
              parts += 1
              checksums << digest_class.digest(chunk)
            end
            [digest_class.hexdigest(checksums.join('')), parts.to_s].join('-')
          end
      end
    end
  end
end
