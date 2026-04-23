defmodule WhisprNotifications.RedisConfigTest do
  @moduledoc """
  Unit tests for the Redis connection options builder.

  The most important guarantee covered here is that `:username` is propagated
  to the top-level Redix opts in sentinel mode — Redis 6+ with ACL enabled
  rejects single-argument AUTH commands (`WRONGPASS`), so the username must
  reach the master node connection (and not only the sentinel discovery).

  Credential-shaped fixtures are generated at runtime so the test source
  contains no hard-coded username/password literals.
  """

  use ExUnit.Case, async: false

  alias WhisprNotifications.RedisConfig

  setup do
    previous = Application.get_env(:whispr_notification, :redis)
    on_exit(fn -> restore_redis_env(previous) end)
    :ok
  end

  describe "direct mode" do
    test "returns host/port/database with optional username and password" do
      user = random_value("user")
      auth = random_value("auth")

      put_redis(
        mode: "direct",
        host: "redis.example.com",
        port: 6380,
        database: 2,
        username: user,
        password: auth
      )

      opts = RedisConfig.build()

      assert Keyword.get(opts, :host) == "redis.example.com"
      assert Keyword.get(opts, :port) == 6380
      assert Keyword.get(opts, :database) == 2
      assert Keyword.get(opts, :username) == user
      assert Keyword.get(opts, :password) == auth
      refute Keyword.has_key?(opts, :sentinel)
    end

    test "omits :username and :password when nil or empty" do
      put_redis(mode: "direct", host: "localhost", port: 6379, username: nil, password: "")

      opts = RedisConfig.build()

      refute Keyword.has_key?(opts, :username)
      refute Keyword.has_key?(opts, :password)
    end
  end

  describe "sentinel mode" do
    test "propagates :username to the top level so AUTH master uses two arguments" do
      user = random_value("user")
      master_auth = random_value("master")
      sentinel_auth = random_value("sentinel")

      put_redis(
        mode: "sentinel",
        sentinels: "s1:26379,s2:26379",
        master_name: "mymaster",
        username: user,
        password: master_auth,
        sentinel_password: sentinel_auth
      )

      opts = RedisConfig.build()

      # Top-level :username + :password → Redix sends `AUTH <user> <auth>`
      # on the master connection (Redis 6+ ACL-compatible).
      assert Keyword.get(opts, :username) == user,
             "Expected :username at top level (Redix uses it for the master AUTH)."

      assert Keyword.get(opts, :password) == master_auth

      # Sentinel discovery uses its own (independent) credential.
      sentinel_cfg = Keyword.fetch!(opts, :sentinel)
      assert Keyword.get(sentinel_cfg, :group) == "mymaster"
      assert Keyword.get(sentinel_cfg, :password) == sentinel_auth

      assert Keyword.get(sentinel_cfg, :sentinels) ==
               [[host: "s1", port: 26_379], [host: "s2", port: 26_379]]
    end

    test "omits :username when REDIS_USERNAME is not configured" do
      auth = random_value("auth")

      put_redis(
        mode: "sentinel",
        sentinels: "s1:26379",
        master_name: "mymaster",
        password: auth
      )

      opts = RedisConfig.build()

      refute Keyword.has_key?(opts, :username)
      assert Keyword.get(opts, :password) == auth
    end

    test "raises when REDIS_SENTINELS is missing" do
      put_redis(mode: "sentinel", master_name: "mymaster")

      assert_raise RuntimeError, ~r/REDIS_SENTINELS is required/, fn ->
        RedisConfig.build()
      end
    end

    test "raises when REDIS_MASTER_NAME is missing" do
      put_redis(mode: "sentinel", sentinels: "s1:26379")

      assert_raise RuntimeError, ~r/REDIS_MASTER_NAME is required/, fn ->
        RedisConfig.build()
      end
    end
  end

  describe "parse_sentinels/1" do
    test "parses a comma-separated list of host:port" do
      assert RedisConfig.parse_sentinels("s1:26379,s2:26380") ==
               [[host: "s1", port: 26_379], [host: "s2", port: 26_380]]
    end

    test "defaults the port to 26379 when only the host is given" do
      assert RedisConfig.parse_sentinels("s1") == [[host: "s1", port: 26_379]]
    end
  end

  defp put_redis(config), do: Application.put_env(:whispr_notification, :redis, config)

  defp restore_redis_env(nil), do: Application.delete_env(:whispr_notification, :redis)
  defp restore_redis_env(prev), do: Application.put_env(:whispr_notification, :redis, prev)

  # Builds a fresh fixture string per call. Keeps secret-shaped literals out
  # of the test source so GitGuardian / similar scanners don't flag fixtures.
  defp random_value(prefix) do
    prefix <> "-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
  end
end
