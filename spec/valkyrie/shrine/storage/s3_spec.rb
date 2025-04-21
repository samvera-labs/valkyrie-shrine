# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Valkyrie::Shrine::Storage::S3 do
  let(:instance) { described_class.new(bucket: bucket, client: s3_client, prefix: storage_prefix) }

  let(:bucket) { "my-bucket" }
  let(:s3_helper) { S3Helper.new }
  let(:s3_client) { s3_helper.client }
  let(:s3_cache) { s3_helper.s3_cache }

  let(:object_id) { "object/id" }

  before do
    s3_cache[bucket] = {}
  end

  describe "#list_object_ids" do
    let(:version1) { storage_prefix.blank? ? "#{object_id}_v-1" : "#{storage_prefix}/#{object_id}_v-1" }
    let(:version2) { storage_prefix.blank? ? "#{object_id}_v-2" : "#{storage_prefix}/#{object_id}_v-2" }

    context "with no storage prefix" do
      let(:storage_prefix) { nil }

      before do
        s3_cache[bucket] = { version1 => {}, version2 => {} }
      end

      it "returns object id's associated with the prefix" do
        expect(instance.list_object_ids(id_prefix: object_id))
          .to contain_exactly("#{object_id}_v-1", "#{object_id}_v-2")
      end
    end

    context "with storage prefix" do
      let(:storage_prefix) { "1234" }

      before do
        s3_cache[bucket] = { version1 => {}, version2 => {} }
      end

      it "returns object id's associated with the prefix" do
        expect(instance.list_object_ids(id_prefix: object_id))
          .to contain_exactly("#{object_id}_v-1", "#{object_id}_v-2")
      end
    end
  end

  describe "#move_to" do
    let(:source_storage_id) { storage_prefix.blank? ? object_id : "#{storage_prefix}/#{object_id}" }
    let(:destination_id) { "#{object_id}_v-1" }
    let(:destination_storage_id) { storage_prefix.blank? ? destination_id : "#{storage_prefix}/#{destination_id}" }

    context "with no storage prefix" do
      let(:storage_prefix) { nil }

      before do
        s3_cache[bucket] = { source_storage_id => {} }
      end

      it "move the file to destination" do
        destination_key = instance.move_to(id: object_id, destination_id: destination_id)
        expect(destination_key).to end_with(destination_storage_id)
        expect(s3_cache[bucket].keys).to contain_exactly(destination_storage_id)
      end
    end

    context "with storage prefix" do
      let(:storage_prefix) { "1234" }

      before do
        s3_cache[bucket] = { source_storage_id => {} }
      end

      it "move the file to destination" do
        destination_key = instance.move_to(id: object_id, destination_id: destination_id)
        expect(destination_key).to end_with(destination_storage_id)
        expect(s3_cache[bucket].keys).to contain_exactly(destination_storage_id)
      end
    end
  end
end
