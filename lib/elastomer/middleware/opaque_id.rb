require 'securerandom'

module Elastomer
  module Middleware

    # This Faraday middleware implements the "X-Opaque-Id" request / response
    # headers for ElasticSearch. The X-Opaque-Id header, when provided on the
    # request header, will be returned as a header in the response. This is
    # useful in environments which reuse connections to ensure that cross-talk
    # does not occur between two requests.
    #
    # The SecureRandom lib is used to generate a UUID string for each request.
    # This value is used as the content for the "X-Opaque-Id" header. If the
    # value is different between the request and the response, then an
    # `Elastomer::Client::OpaqueIdError` is raised. In this case no response
    # will be returned.
    #
    # See [ElasticSearch "X-Opaque-Id"
    # header](https://github.com/elasticsearch/elasticsearch/issues/1202)
    # for more details.
    class OpaqueId < ::Faraday::Middleware
      X_OPAQUE_ID = 'X-Opaque-Id'.freeze

      # Just an initializer.
      def initialize( *args, &block )
        @counter = 0
        super(*args, &block)
      end

      # Faraday middleware implementation.
      #
      # env - Faraday environment Hash
      #
      # Returns the environment Hash
      def call( env )
        uuid = generate_uuid.freeze
        env[:request_headers][X_OPAQUE_ID] = uuid

        @app.call(env).on_complete do |renv|
          if uuid != renv[:response_headers][X_OPAQUE_ID]
            raise ::Elastomer::Client::OpaqueIdError, "conflicting 'X-Opaque-Id' headers"
          end
        end
      end

      # Generate a UUID using the built-in SecureRandom class. This can be a
      # little slow at times, so we will reuse the same UUID and append an
      # incrementing counter. This code is definitely not thread safe, so the
      # Faraday connection should not be shared amongst threads.
      #
      # Returns the UUID string.
      def generate_uuid
        if 0 == @counter % 0xffff
          @counter = 0
          @base_uuid = (SecureRandom.uuid + '-%04x').freeze
        end

        @counter += 1
        @base_uuid % @counter
      end

    end  # OpaqueId
  end  # Middleware

  # Error raised when a conflict is detected between the UUID sent in the
  # 'X-Opaque-Id' request header and the one received in the response header.
  Client::OpaqueIdError = Class.new Client::Error

end  # Elastomer

Faraday.register_middleware :request,
  :opaque_id => ::Elastomer::Middleware::OpaqueId
