# frozen_string_literal: true

require 'spec_helper'
require 'valkyrie'
require 'valkyrie/specs/shared_specs'
require 'shrine/storage/s3'
require 'action_dispatch'
include ActionDispatch::TestProcess

RSpec.describe Valkyrie::Storage::Shrine do
  let(:s3_adapter) { Shrine::Storage::S3.new(bucket: "my-bucket", client: client, prefix: "1234") }
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
end
