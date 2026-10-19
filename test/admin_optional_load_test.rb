# frozen_string_literal: true

require "test_helper"

class AdminOptionalLoadTest < Minitest::Test
  ADMIN_DIR = File.expand_path("../lib/recording_studio_notifications/admin", __dir__)

  def test_admin_definition_files_load_when_recording_studio_admin_is_absent
    Dir["#{ADMIN_DIR}/*.rb"].sort.each do |path|
      source = File.read(path)

      assert_includes source, "return unless defined?(RecordingStudioAdmin)", path
    end

    script = <<~RUBY
      ADMIN_DIR = #{ADMIN_DIR.inspect}
      Dir[File.join(ADMIN_DIR, "*.rb")].sort.each do |path|
        load path
      end
      abort "RecordingStudioAdmin leaked into the isolated load" if defined?(RecordingStudioAdmin)
    RUBY

    output = IO.popen(["ruby", "-e", script], err: [:child, :out], &:read)

    assert_equal 0, $?.exitstatus, output
  end
end
