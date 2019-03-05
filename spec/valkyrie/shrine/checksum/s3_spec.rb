# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Valkyrie::Shrine::Checksum::S3 do
  let(:file) { StringIO.new(File.read('spec/fixtures/files/example.tif')) }
  let(:result) { double }

  context 'Below multipart threshold' do
    let(:instance) { described_class.new }
    let(:etag) { '4174f0b23dba53e252ec0385cf2a2db9' }

    it '#checksum_for' do
      expect(instance.checksum_for(file)).to eq(etag)
    end
  end

  context 'Above multipart threshold' do
    let(:instance) { described_class.new(threshold: 25_000, part_size: 16_384) }
    let(:etag) { 'b995aa1abb265c785a1576c282f218bf-13' }

    it '#checksum_for' do
      expect(instance.checksum_for(file)).to eq(etag)
    end
  end
end
