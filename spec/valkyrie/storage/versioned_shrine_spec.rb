# frozen_string_literal: true

require 'spec_helper'
require 'valkyrie'
require 'valkyrie/specs/shared_specs'
require 'shrine/storage/s3'
require 'action_dispatch'
include ActionDispatch::TestProcess

RSpec.describe Valkyrie::Storage::VersionedShrine do
  let(:s3_adapter) { Valkyrie::Shrine::Storage::S3.new(bucket: "my-bucket", client: client) }
  let(:storage_adapter) { described_class.new(s3_adapter, verifier, identifier_prefix: identifier_prefix) }
  let(:client) { S3Helper.new.client }

  let(:protocol) { Valkyrie::Storage::Shrine::PROTOCOL }
  let(:identifier_prefix) { "1234" }
  let(:protocol_with_prefix) { [identifier_prefix, protocol].reject(&:blank?).join("-") }

  let(:verifier) { NullVerifier }
  let(:resource) { ExampleResource.new(id: "fake-resource-id") }
  let(:file) { Rack::Test::UploadedFile.new(StringIO.new("Test Content"), "text/plain", true, original_filename: "demo.txt") }
  let(:uploaded_file) { storage_adapter.upload(file: file, original_filename: "text.txt", resource: resource, fake_upload_argument: true) }

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

    client.create_bucket(bucket: 'my-bucket')
  end

  after do
    Object.send(:remove_const, :ExampleResource)
    Object.send(:remove_const, :NullVerifier)
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
    before { uploaded_file }

    it "upload a versioned file" do
      allow(s3_adapter).to receive(:open).and_call_original

      uploaded_version = storage_adapter.upload_version(id: uploaded_file.id, file: version_file)

      uploaded_version.read
      expect(s3_adapter).to have_received(:open)
    end
  end

  describe "#find_by" do
    before do
      uploaded_file
      uploaded_version
    end

    it "find the latest versioned file" do
      expect(storage_adapter.find_by(id: uploaded_file.id).id).to eq(uploaded_version.id)
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
      let!(:previous_version_id) { storage_adapter.version_files(id: uploaded_file.id).map(&:id).last }

      it "excludes versions with deletion marker" do
        expect(find_versions.map(&:id)).to include(previous_version_id)

        versions_deleted = storage_adapter.delete(id: previous_version_id)

        expect(versions_deleted.first.deletion_marker?).to eq(true)
        expect(storage_adapter.find_versions(id: uploaded_file.id).map(&:id))
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
      it "includes versioned files with deletion marker" do
        versions_deleted = storage_adapter.delete(id: uploaded_version.id)

        expect(versions_deleted.first.deletion_marker?).to eq(true)
        expect(storage_adapter.version_files(id: uploaded_file.id).map(&:id))
          .to include(versions_deleted.first.id)
      end
    end
  end

  describe "#delete" do
    before do
      uploaded_file
      uploaded_version
    end

    context "a versioned file assiciated with the given identifier" do
      subject(:list_object_ids) { s3_adapter.list_object_ids(id_prefix: shrine_id_uploaded).sort.reverse }

      let(:shrine_id_uploaded) { uploaded_file.id.to_s.split(protocol).last }
      let(:shrine_id_versioned) { uploaded_version.id.to_s.split(protocol).last }

      it "marks the versioned file with deletion marker" do
        versions_deleted = storage_adapter.delete(id: uploaded_version.id).map(&:id).map(&:id)
        expect(versions_deleted)
          .to contain_exactly("#{uploaded_version.id}-deletionmarker")
        expect(s3_adapter.list_object_ids(id_prefix: shrine_id_uploaded).sort.reverse)
          .to include("#{shrine_id_versioned}-deletionmarker")
      end
    end

    context "with all versioned files assiciated with the given identifier" do
      let!(:version_files) { storage_adapter.version_files(id: uploaded_file.id) }

      it "marks all version files' identifiers with deletion marker" do
        expect(storage_adapter.version_files(id: uploaded_file.id).size).to eq(2)
        expect(storage_adapter.delete(id: uploaded_file.id).map(&:id).map(&:id))
          .to contain_exactly("#{version_files.first.id}-deletionmarker",
                              "#{version_files.last.id}-deletionmarker")
      end
    end
  end

  describe "#version_id" do
    subject(:version_id) { storage_adapter.version_id(id) }

    before do
      uploaded_file
      uploaded_version
    end

    context "with a versioned ID" do
      let(:id) { uploaded_version.id }

      it "returns the versioned ID" do
        expect(version_id).to be_a(Valkyrie::Storage::VersionedShrine::VersionId)
        expect(version_id.id).to eq(uploaded_version.id)
      end
    end

    context "converts a referenced version ID" do
      let(:id) { Valkyrie::ID.new("#{uploaded_version.id.to_s.split('v-').first}_v-current") }

      it "returns the latest versioned ID" do
        expect(version_id).to be_a(Valkyrie::Storage::VersionedShrine::VersionId)
        expect(version_id.id).to eq(uploaded_version.id)
      end
    end
  end
end
