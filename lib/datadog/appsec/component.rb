# typed: false
# frozen_string_literal: true

require_relative 'processor'

module Datadog
  module AppSec
    # Core-pluggable component for AppSec
    class Component
      class << self
        def build_appsec_component(settings)
          return unless settings.appsec.enabled

          new(settings)
        end
      end

      attr_reader :processor

      def initialize(settings)
        @processor = Processor.new
      end

      def shutdown!
        processor.finalize if processor
        @processor = nil
      end
    end
  end
end
