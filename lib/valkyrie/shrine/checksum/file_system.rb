# frozen_string_literal:true

module Valkyrie
  module Shrine
    module Checksum
      class FileSystem < Base
        def calculate_checksum(result)
          checksum_for(result.io)
        end
      end
    end
  end
end
