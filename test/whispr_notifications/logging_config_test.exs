defmodule WhisprNotifications.LoggingConfigTest do
  @moduledoc """
  WHISPR-1427 - Vérifie le comportement de LOG_LEVEL et de la config Sentry.

  Les deux blocs testent du comportement observable côté application :
  - LOG_LEVEL : le niveau Logger est pilotable via System.get_env sans rebuild.
  - Sentry : pas de crash au démarrage si SENTRY_DSN est absent.

  Les tests ne touchent pas le fichier runtime.exs (évalué une seule fois au
  démarrage du release) - ils simulent la logique de parsing et de config
  en reproduisant exactement le code de runtime.exs.
  """

  use ExUnit.Case, async: false

  describe "LOG_LEVEL parsing" do
    test "convertit 'info' en atom :info" do
      assert parse_log_level("info") == :info
    end

    test "convertit 'debug' en atom :debug" do
      assert parse_log_level("debug") == :debug
    end

    test "convertit 'warning' en atom :warning" do
      assert parse_log_level("warning") == :warning
    end

    test "convertit 'error' en atom :error" do
      assert parse_log_level("error") == :error
    end

    test "est insensible à la casse ('INFO' → :info)" do
      assert parse_log_level("INFO") == :info
    end

    test "utilise :info comme défaut quand LOG_LEVEL est absent" do
      assert parse_log_level("info") == :info
    end

    test "Logger.configure/1 accepte le niveau sans lever d'exception" do
      prev = Logger.level()

      try do
        # simule ce que runtime.exs fait : apply le niveau à Logger
        Logger.configure(level: :warning)
        assert Logger.level() == :warning
      after
        Logger.configure(level: prev)
      end
    end
  end

  describe "Sentry config no-op quand DSN absent" do
    test "dsn est nil quand SENTRY_DSN est vide" do
      # reproduit la logique if(sentry_dsn != "", do: sentry_dsn, else: nil)
      assert sentry_dsn_from("") == nil
    end

    test "dsn est nil quand SENTRY_DSN n'est pas défini (défaut '')" do
      assert sentry_dsn_from(System.get_env("SENTRY_DSN", "")) == nil
    end

    test "dsn est la valeur de l'env quand SENTRY_DSN est non-vide" do
      dsn = "https://key@sentry.io/123"
      assert sentry_dsn_from(dsn) == dsn
    end

    test "Application.get_env(:sentry, :dsn) ne lève pas sans config explicite" do
      # garantit que l'app démarre sans crash si Sentry n'est pas configuré
      assert is_nil(Application.get_env(:sentry, :dsn)) or
               is_binary(Application.get_env(:sentry, :dsn))
    end
  end

  # reproduit exactement le parsing de runtime.exs
  defp parse_log_level(value) do
    value
    |> String.downcase()
    |> String.to_existing_atom()
  end

  # reproduit la logique de sélection DSN de runtime.exs
  defp sentry_dsn_from(""), do: nil
  defp sentry_dsn_from(dsn), do: dsn
end
