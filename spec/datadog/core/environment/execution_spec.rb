# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/environment/execution'

RSpec.describe Datadog::Core::Environment::Execution do
  describe '#development?' do
    subject(:development?) { described_class.development? }

    context 'when in an RSpec test' do
      it { is_expected.to eq(true) }
    end

    context 'when not in an RSpec test' do
      # RSpec is detected through the $PROGRAM_NAME.
      # Changing it will make RSpec detection to return false.
      #
      # We change the $PROGRAM_NAME instead of stubbing
      # `Datadog::Core::Environment::Execution.rspec?` because
      # otherwise we'll have no real test for non-RSpec cases.
      around do |example|
        begin
          original = $PROGRAM_NAME
          $PROGRAM_NAME = 'not-rspec'
          example.run
        ensure
          $PROGRAM_NAME = original
        end
      end

      let(:repl_script) do
        <<-RUBY
          # Load the working directory version of `ddtrace`
          lib = File.expand_path('lib', __dir__)
          $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
          require 'datadog/core/environment/execution'

          # Print actual value to STDERR, as STDOUT tends to have more noise in REPL sessions.
          STDERR.print Datadog::Core::Environment::Execution.development?
        RUBY
      end

      it 'ensure RSpec detection returns false' do
        is_expected.to eq(false)
      end

      context 'when in an IRB session' do
        it 'returns true' do
          _, err = Bundler.with_clean_env do # Ruby 2.6 does not have irb by default in a bundle, but has it outside of it.
            Open3.capture3('irb', '--noprompt', '--noverbose', stdin_data: repl_script)
          end
          expect(err).to end_with('true')
        end
      end

      context 'when in a Pry session' do
        it 'returns true' do
          Tempfile.create('test') do |f|
            f.write(repl_script)
            f.close

            out, = Open3.capture2e('pry', '-f', '--noprompt', f.path)
            expect(out).to eq('true')
          end
        end
      end

      context 'when in a Minitest test' do
        before { skip('Minitest not in bundle') unless Gem.loaded_specs['minitest'] }

        it 'returns true' do
          expect_in_fork do
            # Minitest reads CLI arguments, but the current process has RSpec
            # arguments that are not relevant (nor compatible) with Minitest.
            # This happens inside a fork, thus we don't have to reset it.
            Object.const_set('ARGV', [])

            require 'minitest/autorun'

            is_expected.to eq(true)
          end
        end
      end

      context 'when in a Rails Spring process' do
        before do
          unless PlatformHelpers.ci? || Gem.loaded_specs['spring']
            skip('spring gem not present. In CI, this test is never skipped.')
          end
        end

        let(:script) do
          <<-RUBY
            require 'bundler/inline'

            gemfile(true) do
              source 'https://rubygems.org'
              gem 'spring', '>= 2.0.2'
            end

            # Load the `bin/spring` file, just like a real Spring application would.
            # https://github.com/rails/spring/blob/0a80019e1abdedb3291afb13e8cfb72f3992da90/bin/spring
            ARGV = ['help'] # Let's ask for a simple Spring command, so that it returns quickly.
            load Gem.bin_path('spring', 'spring')

            #{repl_script}
          RUBY
        end

        it 'returns true' do
          _, err, = Open3.capture3('ruby', stdin_data: script)
          expect(err).to end_with('true')
        end
      end

      context 'for Rails' do
        before do
          unless PlatformHelpers.ci? || Gem.loaded_specs['rails']
            skip('rails gem not present. In CI, this test is never skipped.')
          end
        end

        shared_examples 'rails test' do
          it 'returns true' do
            expect_in_fork(timeout_seconds: 30) do
              Tempfile.open('template.rb') do |template|
                template.write(script)
                template.flush

                require 'bundler/inline'

                gemfile(true) do
                  source 'https://rubygems.org'
                  gem 'rails'
                end

                out, err, status = nil
                Dir.mktmpdir do |dir|
                  Dir.chdir(dir) do
                    out, err, status = Bundler.with_clean_env do
                      Open3.capture3('rails', 'new', 'test123', '--minimal', '-m', template.path)
                    end
                  end
                end

                expect(status).to be_success,
                  "Process exited with status #{status.exitstatus}.\n" \
                  "STDOUT (#{out.size} characters):\n#{out}\nSTDERR (#{err.size} characters):\n#{err}"
              end
            end
          end
        end

        let(:load_ddtrace) do
          lib = File.join(Dir.pwd, 'lib')
          <<-RUBY
# Load the working directory version of `ddtrace`
lib = '#{lib}'
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'datadog/core/environment/execution'
          RUBY
        end

        context 'development' do
          let(:script) do
            <<-RUBY
generate(:task, 'namespace', 'task_name')

insert_into_file "lib/tasks/namespace.rake", "

#{load_ddtrace}

raise unless Datadog::Core::Environment::Execution.development?

", after: "task_name: :environment do\n"

raise 'Not detected as development!' unless rake("namespace:task_name")
            RUBY
          end

          include_examples 'rails test'
        end

        context 'testing' do
          let(:script) do
            <<-RUBY
# Create any Rails entity: this will provide us with a test file to execute.
generate(:controller, 'test')

# Add a simple test case that checks if `#development?` returns as expected.
insert_into_file "test/controllers/test_controller_test.rb", "

#{load_ddtrace}

test 'generated test' do
  assert Datadog::Core::Environment::Execution.development?
end
", after: "IntegrationTest\n"

# Execute the Rails app test suite. This will fail if the test we introduced above fails.
after_bundle do
  rails_command("test")
end
            RUBY
          end

          include_examples 'rails test'
        end
      end
    end
  end
end
