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

  describe "#list_objects" do
    let(:version1) { storage_prefix.blank? ? "#{object_id}_v-1" : "#{storage_prefix}/#{object_id}_v-1" }
    let(:version2) { storage_prefix.blank? ? "#{object_id}_v-2" : "#{storage_prefix}/#{object_id}_v-2" }

    context "with no storage prefix" do
      let(:storage_prefix) { nil }

      before do
        s3_cache[bucket] = { version1 => {}, version2 => {} }
      end

      it "returns object id's associated with the prefix" do
        expect(instance.list_objects(id_prefix: object_id).map(&:key))
          .to contain_exactly("#{object_id}_v-1", "#{object_id}_v-2")
      end
    end

    context "with storage prefix" do
      let(:storage_prefix) { "1234" }

      before do
        s3_cache[bucket] = { version1 => {}, version2 => {} }
      end

      it "returns object id's associated with the prefix" do
        expect(instance.list_objects(id_prefix: object_id).map { |obj| obj.key.delete_prefix("#{storage_prefix}/") })
          .to contain_exactly("#{object_id}_v-1", "#{object_id}_v-2")
      end
    end
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

  describe "#delete_objects" do
    subject(:objects_deleted) { instance.delete_objects(objects_to_delete) }

    let(:version1) { storage_prefix.blank? ? "#{object_id}_v-1" : "#{storage_prefix}/#{object_id}_v-1" }
    let(:version2) { storage_prefix.blank? ? "#{object_id}_v-2" : "#{storage_prefix}/#{object_id}_v-2" }
    let(:object_version1) { double(bucket_name: bucket, key: version1) }
    let(:object_version2) { double(bucket_name: bucket, key: version2) }

    context "with no storage prefix" do
      let(:storage_prefix) { nil }
      let(:objects_to_delete) { [object_version1] }

      before do
        s3_cache[bucket] = { version1 => {}, version2 => {} }
      end

      it "deletes an object" do
        expect { objects_deleted }
          .to change { s3_cache[bucket].size }
          .from(2)
          .to(1)
      end

      context "with list of objects" do
        let(:objects_to_delete) { [object_version1, object_version2] }

        it "deletes all objects" do
          expect { objects_deleted }
            .to change { s3_cache[bucket].size }
            .from(2)
            .to(0)
        end
      end
    end

    context "with storage prefix" do
      let(:storage_prefix) { "1234" }
      let(:objects_to_delete) { [object_version1] }

      before do
        s3_cache[bucket] = { version1 => {}, version2 => {} }
      end

      it "deletes an object" do
        expect { objects_deleted }
          .to change { s3_cache[bucket].size }
          .from(2)
          .to(1)
      end

      context "with list of objects" do
        let(:objects_to_delete) { [object_version1, object_version2] }

        it "deletes all objects" do
          expect { objects_deleted }
            .to change { s3_cache[bucket].size }
            .from(2)
            .to(0)
        end
      end
    end
  end
end
