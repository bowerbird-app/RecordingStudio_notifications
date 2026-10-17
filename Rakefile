# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

DUMMY_TEST_FILES = [
  File.expand_path("test/controllers/docs_controller_test.rb", __dir__),
  File.expand_path("test/recording_studio_v3_test.rb", __dir__)
].freeze
DUMMY_GEMFILE = File.expand_path("test/dummy/Gemfile", __dir__)
SIMPLECOV_HELPER = File.expand_path("test/simplecov_helper.rb", __dir__)
DUMMY_APP_ROOT = File.expand_path("test/dummy", __dir__)
TEST_ROOT = File.expand_path("test", __dir__)
ROOT_TEST_EXCLUSIONS = %w[
  test/controllers/docs_controller_test.rb
  test/dummy/**/*_test.rb
  test/recording_studio_v3_test.rb
  test/rename_verification_test.rb
].freeze
DUMMY_BUNDLE_CLEARED_ENV = {
  "BUNDLE_APP_CONFIG" => nil,
  "BUNDLE_BIN_PATH" => nil,
  "BUNDLE_GEMFILE" => DUMMY_GEMFILE,
  "BUNDLE_LOCKFILE" => nil,
  "BUNDLE_PATH" => nil,
  "BUNDLER_SETUP" => nil,
  "BUNDLER_VERSION" => nil,
  "RUBYLIB" => nil,
  "RUBYOPT" => nil
}.freeze

def run_command!(env, *command)
  return if Bundler.with_unbundled_env { system(env, *command) }

  raise "Command failed (#{Process.last_status.exitstatus}): #{command.join(' ')}"
end

def dummy_bundle_env
  dummy_bundle_base_env.merge(DUMMY_BUNDLE_CLEARED_ENV)
end

def dummy_bundle_base_env
  {
    "BUNDLE_GEMFILE" => DUMMY_GEMFILE
  }
end

def run_dummy_suite
  Dir.chdir(DUMMY_APP_ROOT) do
    env = dummy_bundle_env

    run_command!(env, "bundle", "exec", "bin/rails", "db:prepare")
    # bin/rails boots the app before test_helper, so start SimpleCov in this process first.
    run_command!(
      env.merge("SIMPLECOV_COMMAND_NAME" => "dummy"),
      "bundle", "exec", "ruby", "-r#{SIMPLECOV_HELPER}", "bin/rails", "test"
    )
    DUMMY_TEST_FILES.each do |test_file|
      command_name = "dummy-host-#{File.basename(test_file, '.rb')}"
      run_command!(env.merge("SIMPLECOV_COMMAND_NAME" => command_name), "bundle", "exec", "ruby", "-I#{TEST_ROOT}", test_file)
    end
  end
end

def collate_coverage
  require "simplecov"

  result_files = Dir[File.expand_path("coverage/results/**/.resultset.json", __dir__)]
  raise "No coverage results to collate. Run the gem and dummy suites first." if result_files.empty?

  SimpleCov.collate(result_files) do
    root File.expand_path(".", __dir__)
    enable_coverage :branch
    coverage_dir File.expand_path("coverage", __dir__)
    add_filter "/test/"
    add_filter "/config/"
    add_filter "/db/"
    track_files "{app,lib}/**/*.rb"
  end
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"].exclude(*ROOT_TEST_EXCLUSIONS)
  t.verbose = false
end

namespace :test do
  desc "Run rename verification tests to validate gem naming consistency"
  task :rename_verification do
    ruby "test/rename_verification_test.rb", verbose: true
  end

  desc "Run rename verification tests in verbose mode"
  task :rename_verification_verbose do
    ruby "test/rename_verification_test.rb", "--verbose", verbose: true
  end

  desc "Run dummy app integration tests under the dummy app bundle"
  task(:dummy) { run_dummy_suite }

  desc "Collate gem and dummy SimpleCov results into coverage/"
  task(:coverage) { collate_coverage }

  desc "Run gem and dummy app tests, then collate coverage"
  task all: %i[test dummy coverage]
end

namespace :app do
  desc "Run all tests for the gem"
  task test: "test:all"
end

task default: :test
