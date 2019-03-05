# frozen_string_literal: true

require 'spec_helper'
require 'ostruct'

RSpec.describe Valkyrie::Shrine::Checksum::FileSystem do
  let(:io) { StringIO.new(File.read('spec/fixtures/files/example.tif')) }
  let(:result) { double }
  let(:instance) { described_class.new }

  before do
    allow(result).to receive(:io).and_return(io)
  end

  it '#verify_checksum' do
    expect(instance.verify_checksum(io, result)).to be true
  end
end
