defmodule WhisprNotificationsWeb.ErrorJSONTest do
  use ExUnit.Case, async: true

  alias WhisprNotificationsWeb.ErrorJSON

  test "renders 400" do
    assert ErrorJSON.render("400.json", %{}) == %{errors: %{detail: "Bad Request"}}
  end

  test "renders 401" do
    assert ErrorJSON.render("401.json", %{}) == %{errors: %{detail: "Unauthorized"}}
  end

  test "renders 403" do
    assert ErrorJSON.render("403.json", %{}) == %{errors: %{detail: "Forbidden"}}
  end

  test "renders 404" do
    assert ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert ErrorJSON.render("500.json", %{}) == %{errors: %{detail: "Internal Server Error"}}
  end

  test "renders an arbitrary template via Phoenix fallback" do
    assert %{errors: %{detail: _}} = ErrorJSON.render("418.json", %{})
  end
end
