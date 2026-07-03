# frozen_string_literal: true

require "test_helper"

class RootResolverTest < Minitest::Test
  FakeRoot = Struct.new(:id)
  FakeRecording = Struct.new(:root)
  FakeRecordable = Struct.new(:root)

  def setup
    @original_recording_studio = RecordingStudio if defined?(RecordingStudio)
    Object.send(:remove_const, :RecordingStudio) if defined?(RecordingStudio)

    recording_studio = Module.new do
      define_singleton_method(:root_recording_or_self) do |recording|
        recording.root || recording
      end

      define_singleton_method(:root_recording_for) do |recordable|
        recordable.root
      end
    end
    Object.const_set(:RecordingStudio, recording_studio)
  end

  def teardown
    Object.send(:remove_const, :RecordingStudio) if defined?(RecordingStudio)
    Object.const_set(:RecordingStudio, @original_recording_studio) if @original_recording_studio
  end

  def test_resolves_explicit_root_before_recording_or_recordable
    root = FakeRoot.new("root")
    other_root = FakeRoot.new("other")

    assert_same root, RecordingStudioNotifications::Services::RootResolver.call(
      root_recording: root,
      recording: FakeRecording.new(other_root),
      recordable: FakeRecordable.new(other_root)
    )
  end

  def test_consistent_when_recording_and_recordable_share_root
    root = FakeRoot.new("root")

    assert RecordingStudioNotifications::Services::RootResolver.consistent?(
      root_recording: root,
      recording: FakeRecording.new(root),
      recordable: FakeRecordable.new(root)
    )
  end

  def test_inconsistent_when_explicit_root_differs_from_recording_root
    root = FakeRoot.new("root")
    other_root = FakeRoot.new("other")

    refute RecordingStudioNotifications::Services::RootResolver.consistent?(
      root_recording: root,
      recording: FakeRecording.new(other_root)
    )
  end

  def test_rootless_scope_without_resolved_roots_is_consistent
    assert RecordingStudioNotifications::Services::RootResolver.consistent?(
      root_recording: nil,
      recording: nil,
      recordable: nil
    )
  end
end
