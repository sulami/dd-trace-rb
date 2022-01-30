# typed: false
require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/lograge/ext'

module Datadog
  module Tracing
    module Contrib
      module Lograge
        module Configuration
          # Custom settings for the Lograge integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.default { env_to_bool(Ext::ENV_ENABLED, true) }
              o.lazy
            end
          end
        end
      end
    end
  end
end
