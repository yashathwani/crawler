#
# Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
# or more contributor license agreements. Licensed under the Elastic License 2.0;
# you may not use this file except in compliance with the Elastic License 2.0.
#

# frozen_string_literal: true

require_dependency(File.join(__dir__, 'rule'))
require_dependency(File.join(__dir__, 'url_filter'))

module Crawler
  module Data
    module Extraction
      class Ruleset
        def initialize(ruleset, domain)
          @ruleset = ruleset
          @domain = domain
          validate_ruleset

          # initialize these after validating they are arrays
          rules
          url_filters
        end

        def rules
          @rules ||=
            if @ruleset[:rules]&.any?
              @ruleset[:rules].map do |rule|
                Crawler::Data::Extraction::Rule.new(rule)
              end
            else
              []
            end
        end

        def url_filters
          @url_filters ||=
            if @ruleset[:url_filters]&.any?
              @ruleset[:url_filters].map do |filter|
                Crawler::Data::Extraction::UrlFilter.new(filter)
              end
            else
              []
            end
        end

        def url_filtering_rules
          @url_filtering_rules ||= url_filters.map do |filter|
            pattern = Regexp.new(url_pattern(filter.type, filter.pattern))
            Crawler::Data::Rule.new(Crawler::Data::Rule::ALLOW, url_pattern: pattern)
          end
        end

        private

        def url_pattern(type, pattern)
          "\\A#{Regexp.escape(@domain)}#{path_pattern(type, pattern)}"
        end

        def path_pattern(type, pattern)
          case type
          when 'begins'
            pattern_with_wildcard(pattern)
          when 'ends'
            ".*#{pattern_with_wildcard(pattern)}\\z"
          when 'contains'
            ".*#{pattern_with_wildcard(pattern)}"
          when 'regex'
            pattern
          end
        end

        def pattern_with_wildcard(pattern)
          Regexp.escape(pattern).gsub('\*', '.*')
        end

        def validate_ruleset
          if !@ruleset[:rules].nil? && !@ruleset[:rules].is_a?(Array)
            raise ArgumentError, 'Extraction ruleset rules must be an array'
          end

          return unless !@ruleset[:url_filters].nil? && !@ruleset[:url_filters].is_a?(Array)

          raise ArgumentError, 'Extraction ruleset url_filters must be an array'
        end
      end
    end
  end
end
