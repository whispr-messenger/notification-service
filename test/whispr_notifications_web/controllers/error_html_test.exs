defmodule WhisprNotificationsWeb.ErrorHTMLTest do
  use ExUnit.Case, async: true

  alias WhisprNotificationsWeb.ErrorHTML

  test "renders a templated error string" do
    assert ErrorHTML.render("404.html", %{}) == "Error: Not Found"
  end

  test "renders 500" do
    assert ErrorHTML.render("500.html", %{}) == "Error: Internal Server Error"
  end
end
