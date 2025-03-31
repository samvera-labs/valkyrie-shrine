# frozen_string_literal: true

require 'spec_helper'
require 'valkyrie'
require 'valkyrie/specs/shared_specs'
require 'shrine/storage/s3'
require 'action_dispatch'
include ActionDispatch::TestProcess

RSpec.describe Valkyrie::Storage::VersionedShrine do
  let(:s3_adapter) { Valkyrie::Shrine::Storage::S3.new(bucket: "my-bucket", client: client, identifier_prefix: "1234") }
  let(:storage_adapter) { described_class.new(s3_adapter, verifier) }
  let(:client) { S3Helper.new.client }

  let(:file) { Rack::Test::UploadedFile.new(StringIO.new("Test Content"), "text/plain", true, original_filename: "demo.txt") }
  let(:uploaded_file) { storage_adapter.upload(file: file, original_filename: "text.txt", resource: resource, fake_upload_argument: true) }

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
    let(:verifier) { NullVerifier }
    let(:resource) { ExampleResource.new(id: "fake-resource-id") }

    it "only reads from the client when the content is actually read out" do
      allow(s3_adapter).to receive(:open).and_call_original

      uploaded_file

      expect(s3_adapter).not_to have_received(:open)

      uploaded_file.read
      expect(s3_adapter).to have_received(:open)
    end
  end

  describe "#upload_version" do
    let(:verifier) { NullVerifier }
    let(:resource) { ExampleResource.new(id: "fake-resource-id") }

    let(:version_file) { Rack::Test::UploadedFile.new(StringIO.new("Test  Versioned File Content"), "text/plain", true, original_filename: "versioned.txt") }
    let(:uploaded_version) { storage_adapter.upload_version(id: uploaded_file.id, file: version_file) }

    before { uploaded_file }

    it "upload a versioned file" do
      allow(s3_adapter).to receive(:open).and_call_original

      uploaded_version = storage_adapter.upload_version(id: uploaded_file.id, file: version_file)

      uploaded_version.read
      expect(s3_adapter).to have_received(:open)
    end
  end
end
