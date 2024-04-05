# frozen_string_literal: true

require 'bson'
require 'digest'
require 'nokogiri'

module Crawler
  module Data
    # A CrawlResult contains the fetched and extracted content for some CrawlTask.
    class CrawlResult
      attr_reader :id
      attr_reader :url, :status_code, :content_type
      attr_reader :start_time, :end_time, :duration

      delegate :normalized_url, :normalized_hash, :to => :url

      def initialize(url:, status_code:, start_time: Time.now, end_time: Time.now, content_type: 'unknown')
        raise ArgumentError, 'Need a Crawler URL object!' unless url.kind_of?(Crawler::Data::URL)

        @id = BSON::ObjectId.new.to_s
        @url = url
        @status_code = status_code
        @content_type = content_type

        @start_time = start_time
        @end_time = end_time
        @duration = end_time.to_f - start_time.to_f
      end

      # Hide the constructor from the base class
      private_class_method :new

      #---------------------------------------------------------------------------------------------
      def url_hash
        url.normalized_hash
      end

      def site_url
        @site_url ||= Crawler::Data::URL.parse(url.site)
      end

      def to_h
        {
          :id => id.to_s,
          :url_hash => url_hash,
          :url => url.to_s,
          :status_code => status_code,
          :content_type => content_type
        }
      end

      def to_json(*_args)
        to_h.to_json
      end

      def to_s
        "<#{self.class}: id=#{id}, status_code=#{status_code}, url=#{url}, content_type=#{content_type}>"
      end

      def inspect
        to_s
      end

      #---------------------------------------------------------------------------------------------
      def error?
        kind_of?(Error)
      end

      def fatal_error?
        error? && status_code == Error::FATAL_ERROR_STATUS
      end

      def unsupported_content_type?
        kind_of?(UnsupportedContentType)
      end

      def success?
        kind_of?(Success)
      end

      def sitemap?
        kind_of?(Sitemap)
      end

      def html?
        kind_of?(HTML)
      end

      def content_extractable_file?
        kind_of?(ContentExtractableFile)
      end

      def redirect?
        kind_of?(Redirect)
      end
    end
  end
end