# frozen_string_literal: true

require "test_helper"

class DeliverRollupsTaskTest < ActiveSupport::TestCase
  test "deliver_rollups runs the rollup job immediately" do
    performed = false
    with_singleton_method(RecordingStudioNotifications::RollupDeliveryJob, :perform_now, lambda { |*_, **_|
      performed = true
    }) do
      Rails.application.load_tasks
      task = Rake::Task["recording_studio_notifications:deliver_rollups"]
      task.reenable
      task.invoke
    end

    assert performed
  end

  private

  def with_singleton_method(object, method_name, implementation)
    original = object.method(method_name)
    object.define_singleton_method(method_name) do |*args, **kwargs, &block|
      implementation.call(*args, **kwargs, &block)
    end
    yield
  ensure
    object.singleton_class.send(:remove_method, method_name)
    object.define_singleton_method(method_name, original)
  end
end
