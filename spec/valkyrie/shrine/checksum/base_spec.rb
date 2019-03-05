# frozen_string_literal: true

require 'spec_helper'
require 'ostruct'

RSpec.describe Valkyrie::Shrine::Checksum::Base do
  let(:io) { StringIO.new(File.read('spec/fixtures/files/example.tif')) }
  let(:result) { double }
  let(:instance) { described_class.new }
  let(:sha256) { '083faf236c9c79ab24ebc61fa60a02e5d2bfc9cc8a0944dac57ce2b6765deff3' }

  it '.digest_class' do
    expect(described_class.digest_class).to eq(Digest::SHA256)
  end

  it '#digest_class' do
    expect(instance.digest_class).to eq(Digest::SHA256)
  end

  it '#verify_checksum' do
    expect { instance.verify_checksum(io, result) }.to raise_error(NameError)
  end

  it '#checksum_for' do
    expect(instance.checksum_for(io).to_s).to eq(sha256)
  end
end
