# frozen_string_literal: true

require 'spec_helper'
require 'valkyrie'
require 'valkyrie/specs/shared_specs'
require 'shrine/storage/s3'
require 'action_dispatch'
include ActionDispatch::TestProcess

RSpec.describe Valkyrie::Storage::VersionedShrine do
  let(:s3_adapter) { Valkyrie::Shrine::Storage::S3.new(bucket: s3_bucket, client: s3_client) }
  let(:storage_adapter) { described_class.new(s3_adapter, verifier, identifier_prefix: identifier_prefix) }

  let(:s3_bucket) { "my-bucket" }
  let(:s3_client) { S3Helper.new.client }

  let(:protocol) { Valkyrie::Storage::Shrine::PROTOCOL }
  let(:identifier_prefix) { "1234" }
  let(:protocol_with_prefix) { [identifier_prefix, protocol].reject(&:blank?).join("-") }

  let(:verifier) { NullVerifier }
  let(:resource) { ExampleResource.new(id: "fake-resource-id") }
  let(:file) { fixture_file_upload('files/example.tif', 'image/tiff') }
  let(:uploaded_file) { storage_adapter.upload(file: file, original_filename: "example.tif", resource: resource, fake_upload_argument: true) }

  let(:version_file) { Rack::Test::UploadedFile.new(StringIO.new("Test  Versioned File Content"), "text/plain", true, original_filename: "versioned.txt") }
  let(:uploaded_version) { storage_adapter.upload_version(id: uploaded_file.id, file: version_file) }

  before do
    class ExampleResource < Valkyrie::Resource
    end

    class NullVerifier
      def self.verify_checksum(_io, _result)
        true
      end
    end

    s3_client.create_bucket(bucket: s3_bucket)
  end

  after do
    Object.send(:remove_const, :ExampleResource)
    Object.send(:remove_const, :NullVerifier)
  end

  context 'Default verifier' do
    let(:verifier) { nil }

    it_behaves_like 'a Valkyrie::StorageAdapter'
  end

  context 'Custom verifier' do
    let(:verifier) { double }
    it_behaves_like 'a Valkyrie::StorageAdapter'

    before do
      allow(verifier).to receive(:verify_checksum).and_return(true)
    end
  end

  describe "#upload" do
    it "only reads from the client when the content is actually read out" do
      allow(s3_adapter).to receive(:open).and_call_original

      uploaded_file

      expect(s3_adapter).not_to have_received(:open)

      uploaded_file.read
      expect(s3_adapter).to have_received(:open)
    end
  end

  describe "#upload_version" do
    it "upload a versioned file" do
      uploaded_file

      allow(s3_adapter).to receive(:open).and_call_original

      uploaded_version = storage_adapter.upload_version(id: uploaded_file.id, file: version_file)

      uploaded_version.read
      expect(s3_adapter).to have_received(:open)
    end

    context "non-versioned file with the identifier(:id) exists" do
      subject(:list_object_ids) { s3_adapter.list_object_ids(id_prefix: shrine_id_uploaded).sort.reverse }

      # Upload a non-versioned file with Valkyrie::Storage::Shrine and Shrine::Storage::S3
      let(:shrine_s3_adapter) { Shrine::Storage::S3.new(bucket: s3_bucket, client: s3_client) }
      let(:shrine_storage_adapter) { Valkyrie::Storage::Shrine.new(shrine_s3_adapter, verifier, identifier_prefix: identifier_prefix) }
      let!(:uploaded_file) { shrine_storage_adapter.upload(file: file, original_filename: "text.txt", resource: resource, fake_upload_argument: true) }

      let(:shrine_id_uploaded) { uploaded_file.id.to_s.sub(/^#{protocol_with_prefix}/, "") }

      it "renames the file to a versioned file" do
        expect(uploaded_file.version_id.to_s).not_to include("_v-")

        expect(s3_adapter.list_object_ids(id_prefix: shrine_id_uploaded).last).to eq(shrine_id_uploaded)

        uploaded_version

        expect(list_object_ids.size).to eq(2)
        expect(list_object_ids.last).not_to eq(shrine_id_uploaded)
        expect(list_object_ids.last).to include("#{shrine_id_uploaded}_v-")
        expect(list_object_ids.first).to include(uploaded_version.id.to_s.split(protocol_with_prefix).last)
      end
    end
  end

  describe "#find_by" do
    before do
      uploaded_file
      uploaded_version
    end

    it "find the latest versioned file" do
      expect(storage_adapter.find_by(id: uploaded_file.id))
        .to have_attributes(id: uploaded_version.id, version_id: uploaded_version.version_id)
    end
  end

  describe "#find_versions" do
    subject(:find_versions) { storage_adapter.find_versions(id: uploaded_file.id) }

    before do
      uploaded_file
      uploaded_version
    end

    it "find all active versions" do
      expect(find_versions.size).to eq(2)
    end

    context "with versioned file deleted" do
      let!(:previous_version_id) { storage_adapter.version_files(id: uploaded_file.id).last }

      it "excludes versions that are deleted" do
        expect(find_versions.map(&:version_id)).to include(previous_version_id)

        versions_deleted = storage_adapter.delete(id: previous_version_id)

        expect(versions_deleted.first).to eq(previous_version_id)
        expect(storage_adapter.find_versions(id: uploaded_file.id).map(&:version_id))
          .not_to include(previous_version_id)
      end
    end
  end

  describe "#version_files" do
    subject(:version_files) { storage_adapter.version_files(id: uploaded_file.id) }

    before do
      uploaded_file
      uploaded_version
    end

    context "with all versioned files" do
      it "returns all versioned files" do
        expect(version_files.size).to eq(2)
      end
    end

    context "with versioned file deleted" do
      it "excludes deleted versioned file" do
        versions_deleted = storage_adapter.delete(id: uploaded_version.version_id)

        expect(versions_deleted).to include(uploaded_version.version_id)
        expect(storage_adapter.version_files(id: uploaded_file.id))
          .not_to include(versions_deleted.first)
      end
    end
  end

  describe "#delete" do
    let!(:shrine_id_uploaded) { uploaded_file.id.to_s.split(protocol).last }
    let!(:shrine_version_id) { uploaded_version.version_id.to_s.split(protocol).last }

    it "raises FileNotFound error" do
      expect { storage_adapter.delete(id: "a_fake_id_v-version-id") }
        .to raise_error Valkyrie::StorageAdapter::FileNotFound
    end

    context "a versioned file assiciated with the given identifier" do
      subject(:list_object_ids) { s3_adapter.list_object_ids(id_prefix: shrine_id_uploaded).sort.reverse }

      it "deletes the versioned file" do
        versions_deleted = storage_adapter.delete(id: uploaded_version.version_id).map(&:to_s)
        expect(versions_deleted)
          .to contain_exactly(uploaded_version.version_id)
        expect(s3_adapter.list_object_ids(id_prefix: shrine_id_uploaded).sort.reverse)
          .not_to include(shrine_version_id.to_s)
      end
    end

    context "with all versioned files assiciated with the given identifier" do
      let!(:version_files) { storage_adapter.version_files(id: uploaded_file.id) }

      it "deletes all version files" do
        versions_deleted = storage_adapter.delete(id: uploaded_file.id).map(&:to_s)

        expect(versions_deleted)
          .to contain_exactly(version_files.first.to_s,
                              version_files.last.to_s)
        expect(s3_adapter.list_object_ids(id_prefix: shrine_id_uploaded))
          .to be_empty
      end
    end
  end

  describe "#resolve_current" do
    subject(:version_id) { storage_adapter.resolve_current(id) }
    let(:id) { uploaded_version.version_id }

    before do
      uploaded_file
      uploaded_version
    end

    it "returns the versioned ID" do
      expect(version_id.id).to eq(uploaded_version.version_id)
    end

    context "with a base identifier that is not a version" do
      let(:id) { uploaded_version.id }

      it "returns the latest versioned ID" do
        expect(version_id.id).to eq(uploaded_version.version_id)
      end
    end
  end

  describe "VersionId#new_version" do
    subject(:version_id) { Valkyrie::Storage::VersionedShrine::VersionId.new(identifier) }

    let(:identifier) { Valkyrie::ID.new("shrine://a/fake-id") }

    it "creates a version id" do
      expect(version_id.new_version).to include("_v-")
    end

    context "with a timstamp" do
      let(:timestamp) { Time.now.utc - 1 / 24.0 }

      it "creates a version id" do
        expect(version_id.new_version(timestamp: timestamp))
          .to eq("#{identifier}_v-#{timestamp.strftime('%s%L')}")
      end
    end

    context "with a version id" do
      let(:identifier) { Valkyrie::ID.new("shrine://a/fake-id_v-1694195675462560794") }

      it "creates a new version id" do
        expect(version_id.version).to eq("1694195675462560794")
        expect(version_id.new_version).to include("_v-")
        expect(version_id.new_version).not_to eq("1694195675462560794")
      end
    end
  end
end
