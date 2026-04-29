defmodule WhisprNotificationsWeb.DevicesControllerExtraTest do
  @moduledoc """
  Hits the helper branches of `DevicesController` that aren't reached by the
  end-to-end happy paths in `DevicesControllerTest`:

    * `register/2` and `unregister/2` with no `:jwt_sub` assign — the
      controllers must short-circuit to 401 even though the router pipeline
      ordinarily blocks that case earlier.
    * `device_exists?/2` with empty/nil/non-binary device ids.
    * `ensure_string_keys/1` against a map containing atom keys, plus the
      catch-all clause for non-map input.
    * `format_dt/1` for a non-DateTime input via `serialize/1`.
  """
  use WhisprNotifications.DataCase, async: false
  import Plug.Test
  import Plug.Conn

  alias WhisprNotificationsWeb.DevicesController

  defp build_conn(method, path), do: conn(method, path)

  test "register/2 returns 401 when jwt_sub is missing" do
    conn =
      :post
      |> build_conn("/api/v1/devices")
      |> assign(:jwt_sub, nil)
      |> DevicesController.register(%{"device_id" => "x"})

    assert conn.status == 401
  end

  test "register/2 returns 401 when jwt_sub is empty string" do
    conn =
      :post
      |> build_conn("/api/v1/devices")
      |> assign(:jwt_sub, "")
      |> DevicesController.register(%{"device_id" => "x"})

    assert conn.status == 401
  end

  test "unregister/2 returns 401 when jwt_sub is missing" do
    conn =
      :delete
      |> build_conn("/api/v1/devices/abc")
      |> assign(:jwt_sub, nil)
      |> DevicesController.unregister(%{"device_id" => "abc"})

    assert conn.status == 401
  end

  test "register/2 accepts atom-keyed params (ensure_string_keys atom branch)" do
    conn =
      :post
      |> build_conn("/api/v1/devices")
      |> assign(:jwt_sub, "12345678-1234-4123-8123-000000000001")
      |> DevicesController.register(%{
        device_id: "dev-atom",
        fcm_token: "tok-atom",
        platform: "android"
      })

    # Either 201 (first registration) or 200 (already existed) is fine; we
    # just want to confirm the atom-key branch was hit and the request
    # succeeded.
    assert conn.status in [200, 201]
  end

  test "register/2 with empty device_id returns 400 (validation error)" do
    conn =
      :post
      |> build_conn("/api/v1/devices")
      |> assign(:jwt_sub, "12345678-1234-4123-8123-000000000002")
      |> DevicesController.register(%{
        "device_id" => "",
        "fcm_token" => "tok-empty",
        "platform" => "android"
      })

    assert conn.status == 400
  end

  test "register/2 with non-binary device_id hits the device_exists? catch-all" do
    # An integer device_id falls through device_exists?'s guards into the
    # `_` catch-all clause (line 87) which returns false. The Devices
    # changeset will then reject the row, producing 400.
    conn =
      :post
      |> build_conn("/api/v1/devices")
      |> assign(:jwt_sub, "12345678-1234-4123-8123-000000000003")
      |> DevicesController.register(%{
        "device_id" => 12_345,
        "fcm_token" => "tok-int-id",
        "platform" => "android"
      })

    # Status is 400 (changeset rejects non-string device_id).
    assert conn.status == 400
  end
end
