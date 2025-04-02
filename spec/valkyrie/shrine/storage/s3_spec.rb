# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Valkyrie::Shrine::Storage::S3 do
  let(:instance) { described_class.new(bucket: bucket, client: s3_client, prefix: storage_prefix) }

  let(:bucket) { "my-bucket" }
  let(:s3_helper) { S3Helper.new }
  let(:s3_client) { s3_helper.client }
  let(:s3_cache) { s3_helper.s3_cache }

  let(:object_id) { "object/id" }
  let(:version1) { storage_prefix.blank? ? "#{object_id}_v-1" : "#{storage_prefix}/#{object_id}_v-1" }
  let(:version2) { storage_prefix.blank? ? "#{object_id}_v-2" : "#{storage_prefix}/#{object_id}_v-2" }

  before do
    s3_cache[bucket] = {}
  end

  describe "#list_object_ids" do
    context "with no storage prefix" do
      let(:storage_prefix) { nil }

      before do
        s3_cache[bucket] = { version1 => "Version 1 Content", version2 => "Version 2 Content" }
      end

      it "returns object id's associated with the prefix" do
        expect(instance.list_object_ids(id_prefix: object_id))
          .to contain_exactly("#{object_id}_v-1", "#{object_id}_v-2")
      end
    end

    context "with storage prefix" do
      let(:storage_prefix) { "1234" }

      before do
        s3_cache[bucket] = { version1 => "Version 1 Content", version2 => "Version 2 Content" }
      end

      it "returns object id's associated with the prefix" do
        expect(instance.list_object_ids(id_prefix: object_id))
          .to contain_exactly("#{object_id}_v-1", "#{object_id}_v-2")
      end
    end
  end
end
