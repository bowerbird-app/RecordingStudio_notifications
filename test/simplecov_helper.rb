# frozen_string_literal: true

return if ENV["DISABLE_SIMPLECOV"] == "true"
return if defined?(SimpleCov) && SimpleCov.running

begin
  require "simplecov"
rescue LoadError
  return
end

root = File.expand_path("..", __dir__)
command = ENV.fetch("SIMPLECOV_COMMAND_NAME", "gem")

SimpleCov.root(root)
SimpleCov.start do
  enable_coverage :branch
  command_name command
  coverage_dir File.join(root, "coverage", "results", command)
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/db/"
  track_files "{app,lib}/**/*.rb"
end
