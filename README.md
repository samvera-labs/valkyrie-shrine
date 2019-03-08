# Valkyrie::Shrine

[Shrine](http://shrinerb.com/) storage adapter for [Valkyrie](https://github.com/samvera-labs/valkyrie).

[![CircleCI](https://circleci.com/gh/samvera-labs/valkyrie-shrine.svg?style=svg)](https://circleci.com/gh/samvera-labs/valkyrie-shrine)
[![Coverage Status](https://coveralls.io/repos/github/samvera-labs/valkyrie-shrine/badge.svg?branch=master)](https://coveralls.io/github/samvera-labs/valkyrie-shrine?branch=master)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'valkyrie-shrine'
```

## Usage

Follow the Valkyrie [README](https://github.com/samvera-labs/valkyrie) to get a development or production environment up and running. To enable Shrine support, add the following to your application's config/initializers/valkyrie.rb:

```ruby
  # config/initializers/valkyrie.rb
  require 'shrine/storage/s3'
  require 'shrine/storage/file_system'
  require 'valkyrie/storage/shrine/checksum/s3'
  require 'valkyrie/storage/shrine/checksum/file_system'

  Shrine.storages = {
    file: Shrine::Storage::FileSystem.new("public", prefix: "uploads"),
    s3: Shrine::Storage::S3.new(bucket: 'donut-uploads', prefix: 'cache')
  }

  Valkyrie::StorageAdapter.register(
    Valkyrie::Storage::Shrine.new(Shrine.storages[:s3]), :s3
  )

  Valkyrie::StorageAdapter.register(
    Valkyrie::Storage::Shrine.new(Shrine.storages[:file]), :disk
  )
```

Then proceed to configure your application following the [Valkyrie documentation](https://github.com/samvera-labs/valkyrie#sample-configuration-configvalkyrieyml) 

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/samvera-labs/valkyrie-shrine.
