# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_notifications/install/install_generator"

class InstallGeneratorTest < Minitest::Test
  INSTALL_TEMPLATE_PATH = File.expand_path(
    "../lib/generators/recording_studio_notifications/install/templates/INSTALL.md",
    __dir__
  )

  def with_temp_app
    Dir.mktmpdir("generator-test", File.expand_path("..", __dir__)) do |dir|
      FileUtils.mkdir_p(File.join(dir, "app/assets/tailwind"))
      yield dir
    end
  end

  def build_generator(destination_root, options = {})
    RecordingStudioNotifications::Generators::InstallGenerator.new(
      [],
      options,
      destination_root: destination_root
    )
  end

  def test_mount_engine_uses_configured_mount_path
    generator = build_generator(File.expand_path("..", __dir__), mount_path: "/addons/recording")
    routes = []

    generator.stub(:route, ->(value) { routes << value }) do
      generator.mount_engine
    end

    assert_equal ["mount RecordingStudioNotifications::Engine, at: \"/addons/recording\""], routes
  end

  def test_add_tailwind_source_injects_engine_and_flatpack_sources
    with_temp_app do |dir|
      css_path = File.join(dir, "app/assets/tailwind/application.css")
      File.write(css_path, "@import \"tailwindcss\";\n")

      generator = build_generator(dir)

      Rails.stub(:root, Pathname.new(dir)) do
        generator.stub(:say, nil) do
          generator.add_tailwind_source
        end
      end

      css = File.read(css_path)
      assert_tailwind_sources_present(css)
    end
  end

  def test_add_tailwind_source_does_not_duplicate_existing_entries
    with_temp_app do |dir|
      css_path = File.join(dir, "app/assets/tailwind/application.css")
      File.write(css_path, <<~CSS)
        @import "tailwindcss";
        @source "../../../vendor/bundle/ruby/*/bundler/gems/recording_studio_notifications-*/app/views/**/*.erb";
        @source "../../../../../../usr/local/bundle/ruby/*/bundler/gems/recording_studio_notifications-*/app/views/**/*.erb";
        @source "../../../vendor/bundle/ruby/*/bundler/gems/flatpack-*/app/components/**/*.{rb,erb}";
        @source "../../../../../../usr/local/bundle/ruby/*/bundler/gems/flatpack-*/app/components/**/*.{rb,erb}";
      CSS

      generator = build_generator(dir)

      Rails.stub(:root, Pathname.new(dir)) do
        generator.stub(:say, nil) do
          generator.add_tailwind_source
        end
      end

      css = File.read(css_path)
      assert_tailwind_sources_present(css)
      assert_tailwind_sources_count(css, 1)
    end
  end

  def test_add_tailwind_source_reports_missing_tailwind_config
    with_temp_app do |dir|
      FileUtils.rm_rf(File.join(dir, "app/assets/tailwind"))
      generator = build_generator(dir)
      messages = []

      Rails.stub(:root, Pathname.new(dir)) do
        generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
          generator.add_tailwind_source
        end
      end

      assert_includes messages, ["Tailwind CSS not detected. Skipping Tailwind configuration.", :yellow]
      assert_includes messages, ["If you use Tailwind, add these lines to your Tailwind CSS config:", :yellow]
      tailwind_source_lines.each do |line|
        assert_includes messages, ["  #{line}", :yellow]
      end
    end
  end

  def test_add_tailwind_source_reports_manual_configuration_when_import_is_missing
    with_temp_app do |dir|
      css_path = File.join(dir, "app/assets/tailwind/application.css")
      File.write(css_path, "@source \"../local/**/*.erb\";\n")
      generator = build_generator(dir)
      messages = []

      Rails.stub(:root, Pathname.new(dir)) do
        generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
          generator.add_tailwind_source
        end
      end

      assert_equal "@source \"../local/**/*.erb\";\n", File.read(css_path)
      assert_includes messages, ["Could not find @import \"tailwindcss\" in your Tailwind config.", :yellow]
      assert_includes messages, ["Please manually add these lines to your Tailwind CSS config:", :yellow]
      tailwind_source_lines.each do |line|
        assert_includes messages, ["  #{line}", :yellow]
      end
    end
  end

  def test_adds_notification_polling_controller_to_stimulus_loader
    with_temp_app do |dir|
      controllers_path = File.join(dir, "app/javascript/controllers")
      FileUtils.mkdir_p(controllers_path)
      index_path = File.join(controllers_path, "index.js")
      File.write(index_path, <<~JAVASCRIPT)
        import { application } from "controllers/application"
        import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"

        lazyLoadControllersFrom("controllers", application)
      JAVASCRIPT

      generator = build_generator(dir)

      Rails.stub(:root, Pathname.new(dir)) do
        generator.stub(:say, nil) do
          generator.add_notification_polling_controller_loader
        end
      end

      assert_includes File.read(index_path),
                      'lazyLoadControllersFrom("controllers/recording_studio_notifications", application)'
    end
  end

  def test_add_yaml_config_skips_the_file_when_declined
    with_temp_app do |dir|
      generator = build_generator(dir)

      generator.stub(:yes?, false) do
        generator.add_yaml_config
      end

      refute File.exist?(File.join(dir, "config/recording_studio_notifications.yml"))
    end
  end

  def test_add_yaml_config_copies_the_template_when_accepted
    with_temp_app do |dir|
      generator = build_generator(dir)

      generator.stub(:yes?, true) do
        generator.add_yaml_config
      end

      yaml = File.read(File.join(dir, "config/recording_studio_notifications.yml"))
      assert_includes yaml, "default_channels:"
      assert_includes yaml, "allowed_url_hosts:"
    end
  end

  def test_add_tailwind_source_reports_when_every_source_is_already_present
    with_temp_app do |dir|
      css_path = File.join(dir, "app/assets/tailwind/application.css")
      File.write(css_path, ["@import \"tailwindcss\";", *tailwind_source_lines, ""].join("\n"))
      generator = build_generator(dir)
      messages = []

      Rails.stub(:root, Pathname.new(dir)) do
        generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
          generator.add_tailwind_source
        end
      end

      assert_includes messages,
                      ["Tailwind already configured to include RecordingStudioNotifications and FlatPack sources.", :green]
    end
  end

  def test_polling_loader_reports_a_missing_stimulus_index
    with_temp_app do |dir|
      generator = build_generator(dir)
      messages = []

      Rails.stub(:root, Pathname.new(dir)) do
        generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
          generator.add_notification_polling_controller_loader
        end
      end

      assert_includes messages, ["Stimulus controller index not detected. Add this line to your controller loader:", :yellow]
      assert_includes messages,
                      ["  lazyLoadControllersFrom(\"controllers/recording_studio_notifications\", application)", :yellow]
    end
  end

  def test_polling_loader_reports_a_missing_lazy_loader_import
    with_temp_app do |dir|
      controllers_path = File.join(dir, "app/javascript/controllers")
      FileUtils.mkdir_p(controllers_path)
      File.write(File.join(controllers_path, "index.js"), "import { application } from \"controllers/application\"\n")
      generator = build_generator(dir)
      messages = []

      Rails.stub(:root, Pathname.new(dir)) do
        generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
          generator.add_notification_polling_controller_loader
        end
      end

      assert_includes messages, ["Could not find the Stimulus lazy loader. Add this line to your controller loader:", :yellow]
      assert_equal "import { application } from \"controllers/application\"\n",
                   File.read(File.join(controllers_path, "index.js"))
    end
  end

  def test_bundler_install_source_lines_are_empty_when_bundle_path_fails
    generator = build_generator(File.expand_path("..", __dir__))

    Bundler.stub(:bundle_path, ->(*) { raise "bundle path unavailable" }) do
      assert_equal [], generator.send(:bundler_install_source_lines)
    end
  end

  def test_show_readme_displays_install_guide_for_invoke_behavior
    generator = build_generator(File.expand_path("..", __dir__))
    shown_templates = []

    generator.stub(:behavior, :invoke) do
      generator.stub(:readme, ->(template) { shown_templates << template }) do
        generator.show_readme
      end
    end

    assert_equal ["INSTALL.md"], shown_templates
  end

  def test_install_guide_includes_migration_and_host_setup_steps
    install_guide = File.read(INSTALL_TEMPLATE_PATH)

    assert_includes install_guide, "bin/rails generate recording_studio_notifications:migrations"
    assert_includes install_guide, "bin/rails db:migrate"
    assert_includes install_guide, "auth, layout, and current actor integration"
    assert_includes install_guide, "recording_studio_notifications"
  end

  private

  def assert_tailwind_sources_present(css)
    tailwind_source_lines.each do |line|
      assert_includes css, line
    end
  end

  def assert_tailwind_sources_count(css, count)
    tailwind_source_lines.each do |line|
      assert_equal count, css.scan(line).size
    end
  end

  def tailwind_source_lines
    generator = build_generator(File.expand_path("..", __dir__))
    generator.send(:tailwind_source_lines)
  end
end
