# frozen_string_literal: true

require "test_helper"

class RecipientScopeRegistryTest < Minitest::Test
  def test_register_resolve_and_reject_unknown_scopes
    registry = RecordingStudioNotifications::RecipientScopeRegistry.new
    context = RecordingStudioNotifications::RecipientScopeRegistry::Context.new(actor: "ada")

    registry.register(:everyone) { :all }
    registry.register(:with_actor, &:actor)

    assert registry.registered?(:everyone)
    assert registry.registered?(" with_actor ")
    refute registry.registered?(nil)
    assert_equal :all, registry.resolve(:everyone, context)
    assert_equal "ada", registry.resolve("with_actor", context)
    error = assert_raises(ArgumentError) { registry.resolve(:missing, context) }
    assert_includes error.message, "recipient scope is not registered"
  end

  def test_register_requires_a_callable
    registry = RecordingStudioNotifications::RecipientScopeRegistry.new

    assert_raises(ArgumentError) { registry.register(:empty) }
    assert_raises(ArgumentError) { registry.register(" ") { :noop } }
  end
end
