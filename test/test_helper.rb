# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require "minitest/autorun"
require "rails"
require "recording_studio_notifications"

module StubSupport
	def stub(method_name, implementation)
		had_singleton_method = singleton_methods(false).include?(method_name)
		original_method = method(method_name) if had_singleton_method
		singleton_class.send(:remove_method, method_name) if had_singleton_method

		define_singleton_method(method_name) do |*arguments, **keywords, &block|
			if implementation.respond_to?(:call)
				implementation.call(*arguments, **keywords, &block)
			else
				implementation
			end
		end

		yield
	ensure
		singleton_class.send(:remove_method, method_name) if singleton_class.method_defined?(method_name)
		define_singleton_method(method_name, original_method) if original_method
	end
end

Object.include StubSupport
