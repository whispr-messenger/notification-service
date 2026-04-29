defmodule WhisprNotifications.JsonFormatterExtraTest do
  use ExUnit.Case, async: true

  alias WhisprNotifications.JsonFormatter

  @ts {{2026, 4, 22}, {12, 34, 56, 789}}

  test "passes booleans and nil through unchanged" do
    output =
      JsonFormatter.format(:info, "x", @ts,
        active: true,
        disabled: false,
        absent: nil
      )

    payload = Jason.decode!(String.trim(IO.iodata_to_binary(output)))

    assert payload["active"] == true
    assert payload["disabled"] == false
    assert payload["absent"] == nil
  end

  test "serialises tuples as JSON arrays" do
    output =
      JsonFormatter.format(:info, "x", @ts,
        coords: {1, 2, "three"}
      )

    payload = Jason.decode!(String.trim(IO.iodata_to_binary(output)))

    assert payload["coords"] == [1, 2, "three"]
  end

  test "stringifies non-atom non-binary metadata keys via inspect" do
    output =
      JsonFormatter.format(:info, "x", @ts,
        nested: %{42 => "answer", {:a, :b} => "tuple-key"}
      )

    payload = Jason.decode!(String.trim(IO.iodata_to_binary(output)))

    keys = payload["nested"] |> Map.keys()

    # Either int-key or tuple-key inspect form must be present;
    # both go through sanitize_key/1's catch-all clause.
    assert Enum.any?(keys, &(&1 == "42")) or Enum.any?(keys, &String.starts_with?(&1, "{"))
  end

  test "safe_chardata_to_string falls back to inspect for invalid chardata" do
    # Atoms aren't valid chardata; IO.chardata_to_string raises and the
    # safe wrapper inspects.
    output = JsonFormatter.format(:info, :not_chardata, @ts, [])

    payload = Jason.decode!(String.trim(IO.iodata_to_binary(output)))

    assert payload["message"] == ":not_chardata"
  end
end
