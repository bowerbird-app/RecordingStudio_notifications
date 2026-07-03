> **Architecture Documentation**
> *   **Canonical Source:** [bowerbird-app/recording_studio_notifications](https://github.com/bowerbird-app/recording_studio_notifications/tree/main/docs/recording_studio_notifications)
> *   **Last Updated:** December 11, 2025
>
> *Maintainers: Please update the date above when modifying this file.*

---

# Service Objects

Business logic in RecordingStudioNotifications is encapsulated in service objects using the Result monad pattern.

---

## Usage

```ruby
result = RecordingStudioNotifications::Services::ExampleService.call(name: "World")

if result.success?
  puts result.value  # => "Hello, World!"
else
  puts result.error
end
```

## Creating Services

Create your own services by inheriting from `BaseService`:

```ruby
module RecordingStudioNotifications
  module Services
    class MyService < BaseService
      def initialize(param:)
        @param = param
      end

      private

      def perform
        # Your logic here
        success(result_value)
        # or: failure("Error message")
      end
    end
  end
end
```
