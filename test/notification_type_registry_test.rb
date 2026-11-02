# frozen_string_literal: true

require "test_helper"

class NotificationTypeRegistryTest < Minitest::Test
  def setup
    @registry = RecordingStudioNotifications::NotificationTypeRegistry.new
  end

  def test_omitted_channel_options_are_an_empty_frozen_hash
    registered = @registry.register(:plain, label: "Plain")

    assert_equal({}, registered.channel_options)
    assert registered.channel_options.frozen?
    assert_equal :optional_root, registered.scope
    assert_equal :individual, registered.default_cadence
  end

  def test_channel_options_are_stored_with_symbol_keys_and_frozen
    source = {
      "email" => {
        "individual_mailer" => "PageCommentMailer",
        rollup_mailer: "PageCommentRollupMailer"
      }
    }

    registered = @registry.register(
      :page_comment,
      label: "Page comment",
      default_channels: [:in_app],
      available_channels: %i[in_app email],
      channel_options: source
    )

    assert_equal "PageCommentMailer", registered.channel_options.dig(:email, :individual_mailer)
    assert_equal "PageCommentRollupMailer", registered.channel_options.dig(:email, :rollup_mailer)
    assert registered.channel_options.frozen?
    assert registered.channel_options.fetch(:email).frozen?

    source["email"]["individual_mailer"] = "Changed"
    assert_equal "PageCommentMailer", registered.channel_options.dig(:email, :individual_mailer)
    assert_raises(FrozenError) { registered.channel_options[:email][:extra] = "nope" }
  end

  def test_unknown_top_level_register_options_still_raise
    error = assert_raises(ArgumentError) do
      @registry.register(:page_comment, label: "Page comment", individual_mailer: "PageCommentMailer")
    end

    assert_equal "unknown register option: individual_mailer", error.message
    refute @registry.registered?(:page_comment)
  end

  def test_channel_options_must_be_hashes
    error = assert_raises(ArgumentError) do
      @registry.register(:page_comment, label: "Page comment", channel_options: "email")
    end
    assert_equal "channel_options must be a Hash", error.message

    nested = assert_raises(ArgumentError) do
      @registry.register(:page_comment, label: "Page comment", channel_options: { email: "PageCommentMailer" })
    end
    assert_equal "channel_options for email must be a Hash", nested.message

    blank = assert_raises(ArgumentError) do
      @registry.register(:page_comment, label: "Page comment", channel_options: { "" => {} })
    end
    assert_equal "channel_options channel is required", blank.message
  end

  def test_existing_register_options_are_unchanged
    registered = @registry.register(
      :weekly_digest,
      label: "Weekly digest",
      description: "A digest",
      icon: :bell,
      default_channels: [:email],
      required_channels: [],
      available_channels: %i[in_app email],
      scope: :root,
      category: :collaboration,
      creation_action: :create_digest,
      allowed_cadences: %i[individual weekly],
      default_cadence: :weekly,
      required_cadence: :weekly,
      visible_to: ->(recipient) { recipient },
      inbox: false
    )

    assert_equal :weekly_digest, registered.key
    assert_equal "Weekly digest", registered.label
    assert_equal "A digest", registered.description
    assert_equal :bell, registered.icon
    assert_equal [:email], registered.default_channels
    assert_equal [], registered.required_channels
    assert_equal %i[in_app email], registered.available_channels
    assert_equal :root, registered.scope
    assert_equal :collaboration, registered.category
    assert_equal :create_digest, registered.creation_action
    assert_equal %i[individual weekly], registered.allowed_cadences
    assert_equal :weekly, registered.default_cadence
    assert_equal :weekly, registered.required_cadence
    assert_equal false, registered.inbox
    assert_equal({}, registered.channel_options)
    assert registered.visible_to?(:person)
  end
end
