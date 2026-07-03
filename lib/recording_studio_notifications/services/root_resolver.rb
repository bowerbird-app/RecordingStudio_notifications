# frozen_string_literal: true

module RecordingStudioNotifications
  module Services
    class RootResolver
      def self.call(...)
        new(...).call
      end

      def self.consistent?(root_recording:, recording: nil, recordable: nil)
        roots = [
          root_recording,
          root_for_recording(recording),
          root_for_recordable(recordable)
        ].compact

        return true if roots.size < 2

        roots.map { |root| comparable_identifier(root) }.uniq.one?
      end

      def self.root_for_recording(recording)
        return unless recording && defined?(RecordingStudio)

        RecordingStudio.root_recording_or_self(recording)
      rescue ArgumentError
        nil
      end

      def self.root_for_recordable(recordable)
        return unless recordable && defined?(RecordingStudio)

        RecordingStudio.root_recording_for(recordable)
      rescue ArgumentError
        nil
      end

      def initialize(root_recording: nil, recording: nil, recordable: nil)
        @root_recording = root_recording
        @recording = recording
        @recordable = recordable
      end

      def call
        return @root_recording if @root_recording
        return self.class.root_for_recording(@recording) if @recording

        self.class.root_for_recordable(@recordable)
      end

      def self.comparable_identifier(recording)
        if recording.respond_to?(:id) && recording.id.present?
          [recording.class.name, recording.id.to_s]
        else
          [recording.class.name, recording.object_id]
        end
      end
    end
  end
end
