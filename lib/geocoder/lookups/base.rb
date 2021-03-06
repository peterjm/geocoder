require 'net/http'
require 'uri'

unless defined?(ActiveSupport::JSON)
  begin
    require 'rubygems' # for Ruby 1.8
    require 'json'
  rescue LoadError
    raise LoadError, "Please install the 'json' or 'json_pure' gem to parse geocoder results."
  end
end

module Geocoder
  module Lookup
    class Base

      ##
      # Query the geocoding API and return a Geocoder::Result object.
      # Returns +nil+ on timeout or error.
      #
      # Takes a search string (eg: "Mississippi Coast Coliseumf, Biloxi, MS",
      # "205.128.54.202") for geocoding, or coordinates (latitude, longitude)
      # for reverse geocoding. Returns an array of <tt>Geocoder::Result</tt>s.
      #
      def search(query, options = nil)

        # if coordinates given as string, turn into array
        query = query.split(/\s*,\s*/) if coordinates?(query)

        if query.is_a?(Array)
          reverse = true
          query = query.join(',')
        else
          reverse = false
        end

        if options
          reverse_or_options = options.merge(:reverse => reverse)
        else
          reverse_or_options = reverse
        end
        results(query, reverse_or_options).map{ |r| result_class.new(r) }
      end

      ##
      # Return the URL for a map of the given coordinates.
      #
      # Not necessarily implemented by all subclasses as only some lookups
      # also provide maps.
      #
      def map_link_url(coordinates)
        nil
      end


      private # -------------------------------------------------------------

      ##
      # Object used to make HTTP requests.
      #
      def http_client
        protocol = "http#{'s' if Geocoder::Configuration.use_https}"
        proxy_name = "#{protocol}_proxy"
        if proxy = Geocoder::Configuration.send(proxy_name)
          proxy_url = protocol + '://' + proxy
          begin
            uri = URI.parse(proxy_url)
          rescue URI::InvalidURIError
            raise ConfigurationError,
              "Error parsing #{protocol.upcase} proxy URL: '#{proxy_url}'"
          end
          Net::HTTP::Proxy(uri.host, uri.port, uri.user, uri.password)
        else
          Net::HTTP
        end
      end

      ##
      # Geocoder::Result object or nil on timeout or other error.
      #
      def results(query, reverse_or_options = false)
        fail
      end

      ##
      # URL to use for querying the geocoding engine.
      #
      def query_url(query, reverse_or_options = false)
        fail
      end

      ##
      # Class of the result objects
      #
      def result_class
        Geocoder::Result.const_get(self.class.to_s.split(":").last)
      end

      ##
      # Raise exception instead of warning for specified exceptions.
      #
      def raise_error(err)
        raise err if Geocoder::Configuration.always_raise.include?(err.class)
      end


      ##
      # Returns a parsed search result (Ruby hash).
      #
      def fetch_data(query, reverse_or_options = false)
        begin
          parse_raw_data fetch_raw_data(query, reverse_or_options)
        rescue SocketError => err
          raise_error(err) or warn "Geocoding API connection cannot be established."
        rescue TimeoutError => err
          raise_error(err) or warn "Geocoding API not responding fast enough " +
            "(see Geocoder::Configuration.timeout to set limit)."
        end
      end

      ##
      # Parses a raw search result (returns hash or array).
      #
      def parse_raw_data(raw_data)
        if defined?(ActiveSupport::JSON)
          ActiveSupport::JSON.decode(raw_data)
        else
          begin
            JSON.parse(raw_data)
          rescue
            warn "Geocoding API's response was not valid JSON."
          end
        end
      end

      ##
      # Protocol to use for communication with geocoding services.
      # Set in configuration but not available for every service.
      #
      def protocol
        "http" + (Geocoder::Configuration.use_https ? "s" : "")
      end

      ##
      # Fetches a raw search result (JSON string).
      #
      def fetch_raw_data(query, reverse_or_options = false)
        timeout(Geocoder::Configuration.timeout) do
          url = query_url(query, reverse_or_options)
          uri = URI.parse(url)
          unless cache and response = cache[url]
            client = http_client.new(uri.host, uri.port)
            client.use_ssl = true if Geocoder::Configuration.use_https
            response = client.get(uri.request_uri).body
            if cache
              cache[url] = response
            end
          end
          response
        end
      end

      ##
      # The working Cache object.
      #
      def cache
        Geocoder.cache
      end

      ##
      # Is the given string a loopback IP address?
      #
      def loopback_address?(ip)
        !!(ip == "0.0.0.0" or ip.to_s.match(/^127/))
      end

      ##
      # Does the given string look like latitude/longitude coordinates?
      #
      def coordinates?(value)
        value.is_a?(String) and !!value.to_s.match(/^-?[0-9\.]+, *-?[0-9\.]+$/)
      end

      ##
      # Simulate ActiveSupport's Object#to_query.
      # Removes any keys with nil value.
      #
      def hash_to_query(hash)
        require 'cgi' unless defined?(CGI) && defined?(CGI.escape)
        hash.collect{ |p|
          p[1].nil? ? nil : p.map{ |i| CGI.escape i.to_s } * '='
        }.compact.sort * '&'
      end

      def extract_reverse_and_options(reverse_or_options)
        reverse = reverse_or_options
        options = {}
        if reverse_or_options.respond_to?(:has_key?)
          options = reverse_or_options
          reverse = options.has_key?(:reverse) ? options[:reverse] : false
        end
        return reverse, options
      end
    end
  end
end
