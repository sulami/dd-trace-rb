require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace'
require 'semantic_logger'
require 'ddtrace/contrib/semantic_logger/patcher'

RSpec.describe Datadog::Contrib::SemanticLogger::Patcher do
  describe '.patch' do
    it 'adds Instrumentation to ancestors of SemanticLogger::Logging class' do
      described_class.patch

      expect(SemanticLogger::Loggiing.ancestors).to include(Datadog::Contrib::SemanticLogger::Instrumentation)
    end
  end
end
