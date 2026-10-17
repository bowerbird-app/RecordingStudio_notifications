# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_notifications/migrations/migrations_generator"

class MigrationsGeneratorTest < Minitest::Test
  GENERATOR = RecordingStudioNotifications::Generators::MigrationsGenerator

  def test_copies_engine_migrations_with_fresh_timestamps
    with_destination do |dir, generator|
      with_migration_clock(generator) do
        generator.copy_migrations
      end

      copied = Dir.children(File.join(dir, "db/migrate")).sort
      assert_equal engine_migration_count, copied.size
      copied.each do |filename|
        assert_match(/\A\d{14}_/, filename)
        assert File.size(File.join(dir, "db/migrate", filename)).positive?
      end
    end
  end

  def test_skips_a_migration_that_already_exists
    with_destination do |dir, generator|
      File.write(File.join(dir, "db/migrate/20200101000000_create_recording_studio_notifications.rb"), "# existing\n")
      messages = []

      with_migration_clock(generator) do
        generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
          generator.copy_migrations
        end
      end

      names = Dir.children(File.join(dir, "db/migrate"))
      assert_includes names, "20200101000000_create_recording_studio_notifications.rb"
      assert_equal engine_migration_count, names.size
      assert_includes messages, ["  skip  create_recording_studio_notifications.rb (already exists)", :yellow]
      assert_equal "# existing\n", File.read(File.join(dir, "db/migrate/20200101000000_create_recording_studio_notifications.rb"))
    end
  end

  def test_reports_a_missing_migrations_directory
    with_destination do |_dir, generator|
      Dir.mktmpdir do |empty_root|
        messages = []
        GENERATOR.stub(:source_root, empty_root) do
          generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
            generator.copy_migrations
          end
        end

        assert_includes messages, ["No migrations found in RecordingStudioNotifications engine.", :yellow]
      end
    end
  end

  def test_reports_an_empty_migrations_directory
    with_destination do |_dir, generator|
      Dir.mktmpdir do |empty_root|
        FileUtils.mkdir_p(File.join(empty_root, "db/migrate"))
        messages = []

        GENERATOR.stub(:source_root, empty_root) do
          generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
            generator.copy_migrations
          end
        end

        assert_includes messages, ["No migrations found in RecordingStudioNotifications engine.", :yellow]
      end
    end
  end

  private

  def engine_migration_count
    Dir.children(File.expand_path("../db/migrate", __dir__)).size
  end

  def with_destination(&)
    Dir.mktmpdir("migrations-generator") do |dir|
      FileUtils.mkdir_p(File.join(dir, "db/migrate"))
      generator = GENERATOR.new([], {}, destination_root: dir)
      yield dir, generator
    end
  end

  def with_migration_clock(generator, &)
    sequence = 0
    ActiveRecord::Migration.stub(:next_migration_number, lambda { |*|
      sequence += 1
      format("%014d", sequence)
    }) do
      generator.stub(:sleep, ->(*) {}, &)
    end
  end
end
