defmodule WhisprNotificationsWeb.EndpointTest do
  @moduledoc """
  Tests pour le helper `ws_check_origin/1` de l'Endpoint (WHISPR-1353).

  On bascule manuellement `Application.put_env(:whispr_notification, :env, :prod)`
  pour reproduire le comportement prod sans deployer reellement.
  """

  use ExUnit.Case, async: false

  alias WhisprNotificationsWeb.Endpoint

  setup do
    original_env = Application.get_env(:whispr_notification, :env)
    original_cors = System.get_env("CORS_ALLOWED_ORIGINS")

    on_exit(fn ->
      case original_env do
        nil -> Application.delete_env(:whispr_notification, :env)
        value -> Application.put_env(:whispr_notification, :env, value)
      end

      case original_cors do
        nil -> System.delete_env("CORS_ALLOWED_ORIGINS")
        value -> System.put_env("CORS_ALLOWED_ORIGINS", value)
      end
    end)

    :ok
  end

  describe "ws_check_origin/1 hors prod" do
    test "permissif en env :test" do
      Application.put_env(:whispr_notification, :env, :test)

      assert Endpoint.ws_check_origin(URI.parse("https://anywhere.example.com")) == true
    end
  end

  describe "ws_check_origin/1 en prod" do
    setup do
      Application.put_env(:whispr_notification, :env, :prod)
      :ok
    end

    test "raise si CORS_ALLOWED_ORIGINS absent" do
      System.delete_env("CORS_ALLOWED_ORIGINS")

      assert_raise RuntimeError, ~r/must be set in production/, fn ->
        Endpoint.ws_check_origin(URI.parse("https://app.example.com"))
      end
    end

    test "raise si CORS_ALLOWED_ORIGINS vide" do
      System.put_env("CORS_ALLOWED_ORIGINS", "")

      assert_raise RuntimeError, ~r/cannot be empty in production/, fn ->
        Endpoint.ws_check_origin(URI.parse("https://app.example.com"))
      end
    end

    test "raise si CORS_ALLOWED_ORIGINS=* (wildcard interdit)" do
      System.put_env("CORS_ALLOWED_ORIGINS", "*")

      assert_raise RuntimeError, ~r/CORS_ALLOWED_ORIGINS=\* is not allowed/, fn ->
        Endpoint.ws_check_origin(URI.parse("https://app.example.com"))
      end
    end

    test "accepte une origine de la whitelist" do
      System.put_env("CORS_ALLOWED_ORIGINS", "https://app.example.com,https://admin.example.com")

      assert Endpoint.ws_check_origin(URI.parse("https://app.example.com")) == true
    end

    test "rejette une origine inconnue" do
      System.put_env("CORS_ALLOWED_ORIGINS", "https://app.example.com")

      assert Endpoint.ws_check_origin(URI.parse("https://evil.example.com")) == false
    end

    test "trim les espaces autour des entrees" do
      System.put_env("CORS_ALLOWED_ORIGINS", " https://a.test , https://b.test ")

      assert Endpoint.ws_check_origin(URI.parse("https://b.test")) == true
    end

    test "considere le port 443 comme canonique pour https" do
      System.put_env("CORS_ALLOWED_ORIGINS", "https://app.example.com")

      assert Endpoint.ws_check_origin(URI.parse("https://app.example.com:443")) == true
    end
  end
end
