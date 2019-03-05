# frozen_string_literal:true

module Valkyrie
  module Shrine
    module Checksum
      class Base
        def self.digest_class
          Digest::SHA256
        end

        def digest_class
          self.class.digest_class
        end

        def verify_checksum(io, result)
          checksum_for(io) == calculate_checksum(result)
        end

        def checksum_for(io)
          simple_digest(io)
        end

        def simple_digest(io)
          digest_class.new.tap do |result|
            io.rewind
            while (chunk = io.read(16 * 1024))
              result << chunk
            end
          end
        end

        # Subclass is expected to implement #calculate_checksum
      end
    end
  end
end
