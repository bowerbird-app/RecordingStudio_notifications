# frozen_string_literal: true

require "test_helper"

class InboxScopeTest < Minitest::Test
  def setup
    @configuration = RecordingStudioNotifications::Configuration.new
  end

  def test_default_inbox_scope_is_current_root
    assert_equal "current_root", @configuration.default_inbox_scope
    assert_equal "current_root", @configuration.inbox_scope_for(nil)
    assert_equal "current_root", @configuration.inbox_scope_for("")
    assert_equal "current_root", @configuration.inbox_scope_for("nope")
    assert_equal "current_root", @configuration.inbox_scope_for("ALL")
  end

  def test_allowlisted_request_scope_overrides_the_default
    assert_equal "all", @configuration.inbox_scope_for("all")
    assert_equal "all", @configuration.inbox_scope_for(:all)
    assert_equal "current_root", @configuration.inbox_scope_for("current_root")

    @configuration.default_inbox_scope = "all"

    assert_equal "all", @configuration.inbox_scope_for(nil)
    assert_equal "all", @configuration.inbox_scope_for("sideways")
    assert_equal "current_root", @configuration.inbox_scope_for("current_root")
    assert_equal "all", @configuration.to_h.fetch(:default_inbox_scope)
  end

  def test_default_inbox_scope_rejects_unknown_values_and_keeps_the_previous_one
    @configuration.default_inbox_scope = :current_root

    error = assert_raises(ArgumentError) { @configuration.default_inbox_scope = "everywhere" }

    assert_equal "default_inbox_scope must be one of: all, current_root", error.message
    assert_equal "current_root", @configuration.default_inbox_scope
  end

  def test_merge_sets_default_inbox_scope
    @configuration.merge!("default_inbox_scope" => "all")

    assert_equal "all", @configuration.default_inbox_scope
  end
end
