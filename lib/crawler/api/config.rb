# frozen_string_literal: true

require 'active_support/core_ext/numeric/bytes'

require_dependency(File.join(__dir__, '..', '..', 'statically_tagged_logger'))
require_dependency(File.join(__dir__, '..', 'data', 'crawl_result', 'html'))

java_import java.io.ByteArrayInputStream
java_import java.security.cert.CertificateFactory
java_import java.security.cert.X509Certificate

# A crawl config contains all the necessary parameters to start an individual crawl, e.g. the
# domain(s) and seed url(s), where to output the extracted content, etc.
#
module Crawler
  module API
    class Config
      CONFIG_FIELDS = [
        :crawl_id,             # Unique identifier of the crawl (used in logs, etc)
        :crawl_stage,          # Stage name for multi-stage crawls

        :domain_allowlist,     # Array of domain names for restricting which links to follow
        :seed_urls,            # An array or an enumerator of initial URLs to crawl
        :sitemap_urls,         # Array of sitemap URLs to be used for content discovery
        :robots_txt_service,   # Service to fetch robots.txt
        :output_sink,          # The type of output, either :console or :file
        :output_dir,           # If writing to the filesystem, the directory to write to
        :results_collection,   # An Enumerable collection for storing mock crawl results
        :user_agent,           # The User-Agent used for requests made from the crawler.
        :stats_dump_interval,  # How often should we output stats in the logs during a crawl

        # HTTP header settings
        :http_header_service,  # Service to determine the HTTP headers used for requests made from the crawler.
        :http_auth_allowed,    # If HTTP auth is permitted for non-HTTPS URLs.
        :auth,                 # HTTP auth settings.

        # DNS security settings
        :loopback_allowed,         # If loopback is permitted during DNS resolution
        :private_networks_allowed, # If private network IPs are permitted during DNS resolution

        # SSL security settings
        :ssl_ca_certificates,   # An array of custom CA certificates to trust
        :ssl_verification_mode, # SSL verification mode to use for all connections

        # HTTP proxy settings,
        :http_proxy_host,       # Proxy host to use for all requests (default: no proxying)
        :http_proxy_port,       # Proxy port to use for all requests (default: 8080)
        :http_proxy_protocol,   # Proxy host scheme: http (default) or https
        :http_proxy_username,   # Proxy auth user (default: no auth)
        :http_proxy_password,   # Proxy auth password (default: no auth)

        # URL queue configuration
        :url_queue,            # The type of URL queue to be used
        :url_queue_size_limit, # The maximum number of in-flight URLs we can hold. Specific semantics of this setting depend on the queue implementation

        # Crawl-level limits
        :max_duration,         # Maximum duration of a single crawl, in seconds
        :max_crawl_depth,      # Maximum depth to follow links. Seed urls have depth 1.
        :max_unique_url_count, # Maximum number of unique URLs we process before stopping.
        :max_url_length,       # URL length limit
        :max_url_segments,     # URL complexity limit
        :max_url_params,       # URL parameters limit
        :threads_per_crawl,    # Number of threads to use for a single crawl.

        # Request-level limits
        :max_redirects,        # Maximum number of redirects before raising an error
        :max_response_size,    # Maximum HTTP response length before raising an error
        :connect_timeout,      # Timeout for establishing connections.
        :socket_timeout,       # Timeout for open connections.
        :request_timeout,      # Timeout for requests.

        # Extraction limits
        :max_title_size,         # HTML title length limit in bytes
        :max_body_size,          # HTML body length limit in bytes
        :max_keywords_size,      # HTML meta keywords length limit in bytes
        :max_description_size,   # HTML meta description length limit in bytes

        :max_extracted_links_count, # Number of links to extract for crawling
        :max_indexed_links_count,   # Number of links to extract for indexing
        :max_headings_count,        # HTML heading tags count limit

        # Content extraction (from files)
        :content_extraction_enabled, # Enable content extraction of non-HTML files found during a crawl
        :content_extraction_mime_types, # Extract files with the following MIME types

        # Connector configuration
        :connector_configuration, # Configuration settings taken from the crawler's connector document

        # Other crawler tuning settings
        :default_encoding, # Default encoding used for responses that do not specify a charset
        :compression_enabled, # Enable/disable HTTP content compression
        :sitemap_discovery_disabled, # Enable/disable crawling of sitemaps defined in robots.txt
        :head_requests_enabled, # Fetching HEAD requests before GET requests enabled

        :domains_extraction_rules, # Contains domains extraction rules
      ]

      # Please note: These defaults are used in Enterprise Search config parser
      # and in the `Crawler::HttpClient::Config` class.
      # Make sure to check those before renaming or removing any defaults.
      DEFAULTS = {
        :crawl_stage => :primary,

        :sitemap_urls => [],
        :user_agent => "Elastic-Crawler (#{Crawler.version})",
        :stats_dump_interval => 10.seconds,

        :max_duration => 24.hours,
        :max_crawl_depth => 10,
        :max_unique_url_count => 100_000,

        :max_url_length => 2048,
        :max_url_segments => 16,
        :max_url_params => 32,

        :max_redirects => 10,
        :max_response_size => 10.megabytes,

        :ssl_ca_certificates => [],
        :ssl_verification_mode => 'full',

        :http_proxy_port => 8080,
        :http_proxy_protocol => 'http',

        :connect_timeout => 10,
        :socket_timeout => 10,
        :request_timeout => 60,

        :max_title_size => 1.kilobyte,
        :max_body_size => 5.megabytes,
        :max_keywords_size => 512.bytes,
        :max_description_size => 1.kilobyte,

        :max_extracted_links_count => 1000,
        :max_indexed_links_count => 25,
        :max_headings_count => 25,

        :content_extraction_enabled => false,
        :content_extraction_mime_types => [],

        :output_sink => :console,
        :url_queue => :memory_only,
        :threads_per_crawl => 10,

        :default_encoding => 'UTF-8',
        :compression_enabled => true,
        :sitemap_discovery_disabled => false,
        :head_requests_enabled => false,

        :domains_extraction_rules => {}
      }

      # Settings we are not allowed to log due to their sensitive nature
      SENSITIVE_FIELDS = %i[
        auth
        http_header_service
        http_proxy_username
        http_proxy_password
      ]

      # Specific processed configuration options
      attr_reader(*CONFIG_FIELDS)

      # Loggers available within the crawler
      attr_reader :system_logger # for free-text logging
      attr_reader :event_logger  # for structured logs

      def initialize(params = {})
        params = DEFAULTS.merge(params.symbolize_keys)

        # Make sure we don't have any unexpected parameters
        validate_param_names!(params)

        # Assign instance variables based on the values passed into the constructor
        # Please note: we assign all parameters as-is and then validate specific params below
        assign_config_params(params)

        # Configure crawl ID and stage name
        configure_crawl_id!

        # Setup logging for free-text and structured events
        configure_logging!

        # Normalize and validate parameters
        confugure_ssl_ca_certificates!
        configure_domain_allowlist!
        configure_seed_urls!
        configure_robots_txt_service!
        configure_http_header_service!
        configure_sitemap_urls!
      end

      #---------------------------------------------------------------------------------------------
      def to_s
        formatted_fields = CONFIG_FIELDS.map do |k|
          value = SENSITIVE_FIELDS.include?(k) ? '[redacted]' : public_send(k)
          "#{k}=#{value}"
        end
        "<#{self.class}: #{formatted_fields.join('; ')}>"
      end

      #---------------------------------------------------------------------------------------------
      def validate_param_names!(params)
        extra_params = params.keys - CONFIG_FIELDS
        if extra_params.any?
          raise ArgumentError, "Unexpected configuration options: #{extra_params.inspect}"
        end
      end

      def assign_config_params(params)
        params.each do |k, v|
          instance_variable_set("@#{k}", v.dup)
        end
      end

      #---------------------------------------------------------------------------------------------
      # Generate a new crawl id if needed
      def configure_crawl_id!
        @crawl_id ||= BSON::ObjectId.new.to_s
      end

      #---------------------------------------------------------------------------------------------
      def confugure_ssl_ca_certificates!
        ssl_ca_certificates.map! do |cert|
          if cert =~ /BEGIN CERTIFICATE/
            parse_certificate_string(cert)
          else
            load_certificate_from_file(cert)
          end
        end
      end

      #---------------------------------------------------------------------------------------------
      # Parses a PEM-formatted certificate and returns an X509Certificate object for it
      def parse_certificate_string(pem)
        cert_stream = ByteArrayInputStream.new(pem.to_java_bytes)
        cert = CertificateFactory.getInstance('X509').generateCertificate(cert_stream)
        cert.to_java(X509Certificate)
      rescue Java::JavaSecurity::GeneralSecurityException => e
        raise ArgumentError, "Error while parsing an SSL certificate: #{e}"
      end

      #---------------------------------------------------------------------------------------------
      # Loads an SSL certificate from disk and returns it as an X509Certificate object
      def load_certificate_from_file(file_name)
        system_logger.debug("Loading SSL certificate: #{file_name.inspect}")
        cert_content = File.read(file_name)
        parse_certificate_string(cert_content)
      rescue SystemCallError => e
        raise ArgumentError, "Error while loading an SSL certificate #{file_name.inspect}: #{e}"
      end

      #---------------------------------------------------------------------------------------------
      def configure_domain_allowlist!
        raise ArgumentError, 'Needs at least one domain' unless domain_allowlist&.any?
        domain_allowlist.map! do |domain|
          validate_domain!(domain)
          Crawler::Data::Domain.new(domain)
        end
      end

      #---------------------------------------------------------------------------------------------
      def validate_domain!(domain)
        url = URI.parse(domain)
        raise ArgumentError, "Domain #{domain.inspect} does not have a URL scheme" unless url.scheme
        raise ArgumentError, "Domain #{domain.inspect} cannot have a path" unless url.path == ''
        raise ArgumentError, "Domain #{domain.inspect} is not an HTTP(S) site" unless url.kind_of?(URI::HTTP)
      end

      #---------------------------------------------------------------------------------------------
      def configure_seed_urls!
        raise ArgumentError, 'Need at least one seed URL' unless seed_urls&.any?

        # Convert seed URLs into an enumerator if needed
        @seed_urls = seed_urls.each unless seed_urls.kind_of?(Enumerator)

        # Parse and validate all URLs as we access them
        @seed_urls = seed_urls.lazy.map do |seed_url|
          Crawler::Data::URL.parse(seed_url).tap do |url|
            unless url.supported_scheme?
              raise ArgumentError, "Unsupported scheme for a seed URL: #{url}"
            end
          end
        end
      end

      #---------------------------------------------------------------------------------------------
      def configure_robots_txt_service!
        @robots_txt_service ||= Crawler::RobotsTxtService.new(:user_agent => user_agent)
      end

      #---------------------------------------------------------------------------------------------
      def configure_http_header_service!
        @http_header_service ||= Crawler::HttpHeaderService.new(:auth => auth)
      end

      #---------------------------------------------------------------------------------------------
      def configure_sitemap_urls!
        # Parse and validate all URLs
        sitemap_urls.map! do |sitemap_url|
          Crawler::Data::URL.parse(sitemap_url).tap do |url|
            unless url.supported_scheme?
              raise ArgumentError, "Unsupported scheme for a sitemap URL: #{url}"
            end
          end
        end
      end

      #---------------------------------------------------------------------------------------------
      def configure_logging!
        @event_logger = Logger.new(STDOUT)

        # Add crawl id and stage to all logging events produced by this crawl
        base_system_logger = StaticallyTaggedLogger.new(Logger.new(STDOUT))
        @system_logger = base_system_logger.tagged("crawl:#{crawl_id}", crawl_stage)
      end

      #---------------------------------------------------------------------------------------------
      # Returns an event generator used to capture crawl life cycle events
      def events
        @events ||= Crawler::EventGenerator.new(self)
      end

      # Returns the per-crawl stats object used for aggregating crawl statistics
      def stats
        @stats ||= Crawler::Stats.new
      end

      #---------------------------------------------------------------------------------------------
      # Receives a crawler event object and outputs it into relevant systems
      def output_event(event)
        # Log the event
        event_logger << event.to_json + "\n"

        # Count stats for the crawl
        stats.update_from_event(event)
      end
    end
  end
end