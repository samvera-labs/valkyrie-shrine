# frozen_string_literal: true

require 'spec_helper'
require 'valkyrie'
require 'valkyrie/specs/shared_specs'
require 'shrine/storage/s3'
require 'action_dispatch'
include ActionDispatch::TestProcess

RSpec.describe Valkyrie::Storage::Shrine do
  let(:s3_adapter) { Shrine::Storage::S3.new(bucket: "my-bucket", client: client, identifier_prefix: "1234") }
  let(:storage_adapter) { described_class.new(s3_adapter, verifier) }
  let(:file) { fixture_file_upload('files/example.tif', 'image/tiff') }
  let(:client) { S3Helper.new.client }

  before do
    client.create_bucket(bucket: 'my-bucket')
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

  context "when given a custom identifier_prefix" do
    before do
      class PrefixResource < Valkyrie::Resource
      end
    end
    after do
      Object.send(:remove_const, :PrefixResource)
    end
    it "uses it for IDs generated" do
      adapter = described_class.new(s3_adapter, nil, Valkyrie::Storage::Shrine::IDPathGenerator, identifier_prefix: "s3")
      other_adapter = described_class.new(s3_adapter)

      uploaded_file = adapter.upload(file: file, resource: PrefixResource.new(id: SecureRandom.uuid, new_record: false), original_filename: "example.tif")
      expect(adapter.handles?(id: uploaded_file.id)).to eq true

      expect(other_adapter.handles?(id: uploaded_file.id)).to eq false
    end
  end
end
