# frozen_string_literal: true

require_dependency(File.join(__dir__, 'success'))

module Crawler
  module Data
    class CrawlResult::RobotsTxt < CrawlResult::Success
      # Allow constructor to be called on concrete result classes
      public_class_method :new
    end
  end
end