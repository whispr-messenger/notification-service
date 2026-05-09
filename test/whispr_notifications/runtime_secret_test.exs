defmodule WhisprNotifications.RuntimeSecretTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.RuntimeSecret

  describe "validate_secret_key_base!/1" do
    test "accepts a 64-byte secret and returns it unchanged" do
      secret = String.duplicate("a", 64)
      assert RuntimeSecret.validate_secret_key_base!(secret) == secret
    end

    test "accepts a longer secret (mix phx.gen.secret produces 64+)" do
      secret = String.duplicate("z", 96)
      assert RuntimeSecret.validate_secret_key_base!(secret) == secret
    end

    test "raises when the secret is shorter than the minimum" do
      short = String.duplicate("a", 63)

      assert_raise RuntimeError, ~r/SECRET_KEY_BASE must be at least 64 bytes/, fn ->
        RuntimeSecret.validate_secret_key_base!(short)
      end
    end

    test "raises with the actual byte size in the error message" do
      short = "too-short"

      assert_raise RuntimeError, ~r/currently #{byte_size(short)}/, fn ->
        RuntimeSecret.validate_secret_key_base!(short)
      end
    end

    test "raises on empty string" do
      assert_raise RuntimeError, ~r/currently 0/, fn ->
        RuntimeSecret.validate_secret_key_base!("")
      end
    end
  end

  describe "minimum_secret_key_base_bytes/0" do
    test "is 64 bytes (matches mix phx.gen.secret default output)" do
      assert RuntimeSecret.minimum_secret_key_base_bytes() == 64
    end
  end
end
