# frozen_string_literal: true

require 'aws-sdk-s3'

class S3Helper
  def s3_cache
    @s3_cache ||= {}
  end

  def create_bucket
    lambda { |context|
      name = context.params[:bucket]
      return 'BucketAlreadyExists' if s3_cache[name]
      s3_cache[name] = {}
    }
  end

  def delete_object
    lambda { |context|
      bucket = context.params[:bucket]
      key = context.params[:key]
      s3_cache[bucket].delete(key)
      {}
    }
  end

  def head_object
    lambda { |context|
      bucket = context.params[:bucket]
      key = context.params[:key]
      bucket_contents = s3_cache[bucket]
      return 'NoSuchBucket' unless bucket_contents
      obj = bucket_contents[key]
      obj ? { etag: %("#{Digest::MD5.hexdigest(obj)}"), content_length: obj.size } : 'NoSuchKey'
    }
  end

  def get_object # rubocop:disable Naming/AccessorMethodName
    lambda { |context|
      bucket = context.params[:bucket]
      key = context.params[:key]
      bucket_contents = s3_cache[bucket]
      return 'NoSuchBucket' unless bucket_contents
      obj = bucket_contents[key]
      obj ? { body: obj, etag: %("#{Digest::MD5.hexdigest(obj)}"), content_length: obj.size } : 'NoSuchKey'
    }
  end

  def put_object
    lambda { |context|
      bucket = context.params[:bucket]
      key = context.params[:key]
      body = context.params[:body]
      content = body.respond_to?(:read) ? body.read : body
      bucket_contents = s3_cache[bucket]
      return 'NoSuchBucket' unless bucket_contents
      bucket_contents[key] = content
      {}
    }
  end

  def client
    Aws::S3::Client.new(
      stub_responses: {
        create_bucket: create_bucket,
        delete_object: delete_object,
        head_object: head_object,
        get_object: get_object,
        put_object: put_object
      }
    )
  end
end
