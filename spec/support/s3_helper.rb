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

  def copy_object
    lambda { |context|
      bucket = context.params[:bucket]
      key = context.params[:key]
      copy_source = context.params[:copy_source]
      source_bucket = copy_source.split("/", 2).first
      source_bucket_contents = s3_cache[source_bucket]
      bucket_contents = s3_cache[bucket]

      return "NoSuchBucket" unless bucket_contents && source_bucket_contents
      source_key = copy_source.split("/", 2).last
      source = source_bucket_contents[source_key]
      return "NoSuchKey" unless source
      bucket_contents[key] = source
      { copy_object_result: { etag: source[:etag], last_modified: source[:last_modified] } }
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

  def delete_objects
    lambda { |context|
      bucket = context.params[:bucket]
      objs = context.params[:delete][:objects]
      objs.map { |obj| obj[:key] }.each { |k| s3_cache[bucket].delete(k) }
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
      obj ? { etag: obj[:etag], content_length: obj[:content_length], last_modified: obj[:last_modified] } : { status_code: 404, headers: {}, body: '' }
    }
  end

  def get_object # rubocop:disable Naming/AccessorMethodName
    lambda { |context|
      bucket = context.params[:bucket]
      key = context.params[:key]
      bucket_contents = s3_cache[bucket]
      return 'NoSuchBucket' unless bucket_contents
      obj = bucket_contents[key]
      obj || 'NoSuchKey'
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
      etag = %("#{Digest::MD5.hexdigest(content || '')}")
      obj = { body: content, etag: etag, content_length: (content || '').size, last_modified: Time.now.utc }
      bucket_contents[key] = obj
      {}
    }
  end

  def list_objects_v2
    lambda { |context|
      bucket = context.params[:bucket]
      prefix = context.params[:prefix]
      bucket_contents = s3_cache[bucket]
      return "NoSuchBucket" unless bucket_contents
      { contents: bucket_contents.select { |k, _v| k.start_with?(prefix) }
                                 .map { |k, _v| { key: k } } }
    }
  end

  def client
    Aws::S3::Client.new(
      stub_responses: {
        create_bucket: create_bucket,
        copy_object: copy_object,
        delete_object: delete_object,
        delete_objects: delete_objects,
        head_object: head_object,
        list_objects_v2: list_objects_v2,
        get_object: get_object,
        put_object: put_object
      }
    )
  end
end
