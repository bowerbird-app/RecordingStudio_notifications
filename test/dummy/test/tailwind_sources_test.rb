# frozen_string_literal: true

require "test_helper"

class TailwindSourcesTest < ActiveSupport::TestCase
  test "Tailwind @source globs cover installed FlatPack and admin gems" do
    css_path = Rails.root.join("app/assets/tailwind/application.css")
    css_dir = css_path.dirname
    patterns = File.read(css_path).scan(/@source\s+"([^"]+)"/).flatten

    assert_predicate patterns, :any?

    covered_directories = patterns.flat_map do |pattern|
      absolute_pattern = pattern.start_with?("/") ? pattern : File.expand_path(pattern, css_dir)
      directory_glob = absolute_pattern
        .sub(%r{/\*\*/\*\.\{rb,erb\}$}, "")
        .sub(%r{/\*\*/\*\.erb$}, "")
      Dir.glob(directory_glob)
    end

    %w[flat_pack recording_studio_admin].each do |gem_name|
      spec = Bundler.rubygems.find_name(gem_name).first
      assert spec, "Expected #{gem_name} to be bundled"

      components_dir = File.join(spec.full_gem_path, "app/components")
      next unless File.directory?(components_dir)

      assert covered_directories.any? { |directory|
        components_dir == directory || components_dir.start_with?("#{directory}/")
      }, "Tailwind @source globs did not cover #{components_dir}"
    end
  end

  test "layouts always include the compiled Tailwind stylesheet" do
    %w[
      app/views/layouts/application.html.erb
      app/views/layouts/admin.html.erb
      app/views/layouts/flat_pack_sidebar.html.erb
    ].each do |layout_path|
      layout = File.read(Rails.root.join(layout_path))
      assert_includes layout, 'stylesheet_link_tag "tailwind"'
      refute_includes layout, "tailwind_asset_present"
    end
  end
end
