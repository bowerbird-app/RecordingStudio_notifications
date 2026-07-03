# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    class RootResolver
      def self.call(...)
        new(...).call
      end

      def initialize(root_recording: nil, recording: nil, recordable: nil)
        @root_recording = root_recording
        @recording = recording
        @recordable = recordable
      end

      def call
        return @root_recording if @root_recording
        return RecordingStudio.root_recording_or_self(@recording) if @recording && defined?(RecordingStudio)
        return unless @recordable && defined?(RecordingStudio)

        RecordingStudio.root_recording_for(@recordable)
      rescue ArgumentError
        nil
      end
    end
  end
end
