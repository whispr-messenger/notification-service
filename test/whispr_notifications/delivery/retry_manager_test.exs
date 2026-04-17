defmodule WhisprNotifications.Delivery.RetryManagerTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.Delivery.RetryManager

  @base_attempt %{
    device: %{token: "tok", platform: :ios, app: nil},
    payload: %{"aps" => %{}},
    platform: :ios,
    retries: 0
  }

  describe "should_retry?/1" do
    test "returns true when retries is 0" do
      assert RetryManager.should_retry?(%{@base_attempt | retries: 0})
    end

    test "returns true when retries is 2 (below max)" do
      assert RetryManager.should_retry?(%{@base_attempt | retries: 2})
    end

    test "returns false when retries equals max (3)" do
      refute RetryManager.should_retry?(%{@base_attempt | retries: 3})
    end

    test "returns false when retries exceeds max" do
      refute RetryManager.should_retry?(%{@base_attempt | retries: 5})
    end
  end

  describe "next_attempt/1" do
    test "increments retry count by 1" do
      attempt = %{@base_attempt | retries: 1}
      assert RetryManager.next_attempt(attempt).retries == 2
    end

    test "preserves all other fields" do
      attempt = @base_attempt
      next = RetryManager.next_attempt(attempt)

      assert next.device == attempt.device
      assert next.payload == attempt.payload
      assert next.platform == attempt.platform
    end
  end
end
